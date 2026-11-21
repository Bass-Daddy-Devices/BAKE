#!/bin/bash
# Releases BAKE: checks, builds and notarizes (scripts/notarize.sh), signs the update for Sparkle,
# publishes the DMG as a GitHub Release, then updates the feed on bake.bass-daddy.com.
#
#   scripts/release.sh 1.0.0              release 1.0.0 (MARKETING_VERSION must already be 1.0.0)
#   scripts/release.sh 1.0.0 --dry-run    everything but publishing; feed and notes in build/release/site-preview
#   scripts/release.sh 0.9.0 --rehearsal  a GitHub pre-release on the rehearsal feed
#
# Needs: gh (logged in), the BAKE-notary Keychain profile (see notarize.sh), the Sparkle key in the
# Keychain (generate_keys, once), and a clean bake-site checkout at $BAKE_SITE (default ../bake-site).
# If a run stops after creating the GitHub Release, see the message the next run prints.
set -euo pipefail

VERSION="${1:-}"
if [[ $# -gt 0 ]]; then shift; fi
DRY_RUN=0
REHEARSAL=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --rehearsal) REHEARSAL=1 ;;
        *) echo "error: unknown option $arg" >&2; exit 2 ;;
    esac
done
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || { echo "usage: scripts/release.sh <major.minor.patch> [--dry-run] [--rehearsal]" >&2; exit 2; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SITE="${BAKE_SITE:-$ROOT/../bake-site}"
REPO="bassDaddyDevices/BAKE"
SITE_URL="https://bake.bass-daddy.com"
FEED_DIR=""
if [[ $REHEARSAL == 1 ]]; then FEED_DIR="rehearsal/"; fi
FEED_URL="$SITE_URL/${FEED_DIR}appcast.xml"
NOTES="$ROOT/release-notes/$VERSION.md"
TAG="v$VERSION"
DMG_NAME="BAKE-$VERSION.dmg"
DMG_URL="https://github.com/$REPO/releases/download/$TAG/$DMG_NAME"
SPARKLE_BIN="$ROOT/build/packages/artifacts/sparkle/Sparkle/bin"
APPCAST="/usr/bin/python3 $ROOT/scripts/appcast.py"

step() { printf '\n==> %s\n' "$1"; }
fail() { echo "error: $1" >&2; exit 1; }

step "Checking the release is ready"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || fail "the working tree isn't clean"
PROJECT_VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' "$ROOT/BAKE/BAKE.xcodeproj/project.pbxproj" | sort -u | tr '\n' ' ' | xargs)"
if [[ $REHEARSAL == 0 && "$PROJECT_VERSION" != "$VERSION" ]]; then
    fail "the project's MARKETING_VERSION is $PROJECT_VERSION, not $VERSION (bump it in a \"release: $VERSION\" commit)"
fi
if [[ $REHEARSAL == 1 && "$(printf '%s\n%s\n' "$VERSION" "$PROJECT_VERSION" | sort -V | head -n1)" != "$VERSION" || $REHEARSAL == 1 && "$VERSION" == "$PROJECT_VERSION" ]]; then
    fail "a rehearsal version must be lower than the project's MARKETING_VERSION ($PROJECT_VERSION)"
fi
# Rehearsals don't need committed notes.
if [[ $REHEARSAL == 1 && ! -f "$NOTES" ]]; then
    NOTES="$(mktemp)"
    printf 'Update rehearsal build %s. Not a real release.\n' "$VERSION" > "$NOTES"
fi
[[ -f "$NOTES" ]] || fail "release-notes/$VERSION.md is missing"
if [[ $DRY_RUN == 0 ]]; then
    [[ "$(git -C "$ROOT" branch --show-current)" == main ]] || fail "releases are made from main"
    git -C "$ROOT" fetch -q origin main
    [[ "$(git -C "$ROOT" rev-parse HEAD)" == "$(git -C "$ROOT" rev-parse origin/main)" ]] || fail "main isn't equal to origin/main"
fi
gh auth status >/dev/null 2>&1 || fail "gh isn't logged in (gh auth login)"
if [[ -n "$(git -C "$ROOT" ls-remote --tags origin "refs/tags/$TAG")" ]] || gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    EXISTS_MSG="$TAG already exists. If the last run stopped after creating the release, push the bake-site commit by hand (git -C $SITE push origin main). Otherwise delete it (gh release delete $TAG -R $REPO --cleanup-tag --yes) and run again."
    if [[ $DRY_RUN == 1 ]]; then echo "warning: $EXISTS_MSG" >&2; else fail "$EXISTS_MSG"; fi
fi
xcrun notarytool history --keychain-profile "${BAKE_NOTARY_PROFILE:-BAKE-notary}" >/dev/null 2>&1 \
    || fail "the BAKE-notary Keychain profile is missing (see scripts/notarize.sh)"
xcodebuild -resolvePackageDependencies -workspace "$ROOT/BAKE_WORKSPACE.xcworkspace" -scheme BAKE \
    -clonedSourcePackagesDirPath "$ROOT/build/packages" -quiet
PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/BAKE/BAKE/Info.plist")"
[[ "$("$SPARKLE_BIN/generate_keys" -p 2>/dev/null)" == "$PUBLIC_KEY" ]] \
    || fail "the Sparkle key in the Keychain doesn't match SUPublicEDKey in Info.plist"
[[ -d "$SITE/.git" ]] || fail "no bake-site checkout at $SITE (set BAKE_SITE)"
[[ -z "$(git -C "$SITE" status --porcelain)" ]] || fail "the bake-site checkout isn't clean"
[[ "$(git -C "$SITE" branch --show-current)" == main ]] || fail "the bake-site checkout isn't on main"
if [[ $DRY_RUN == 0 ]]; then
    git -C "$SITE" pull -q --ff-only
    [[ -z "$(git -C "$SITE" rev-list origin/main..main)" ]] \
        || fail "the bake-site checkout has commits that aren't on origin/main; push or drop them"
fi

step "Running the tests"
swift test --package-path "$ROOT/BakeCore" >/dev/null || fail "swift test failed"
xcodebuild -workspace "$ROOT/BAKE_WORKSPACE.xcworkspace" -scheme BAKE -destination 'platform=macOS' \
    -derivedDataPath /tmp/bake-dd build -quiet || fail "the app build failed"

COUNT="$(git -C "$ROOT" rev-list --count HEAD)"
BUILD="$COUNT"
SETTINGS="CURRENT_PROJECT_VERSION=$BUILD BAKE_FEED_URL=$FEED_URL"
if [[ $REHEARSAL == 1 ]]; then
    BUILD="$COUNT.${VERSION##*.}"
    SETTINGS="CURRENT_PROJECT_VERSION=$BUILD BAKE_FEED_URL=$FEED_URL MARKETING_VERSION=$VERSION"
fi

step "Building, signing and notarizing $VERSION (build $BUILD)"
BAKE_BUILD_SETTINGS="$SETTINGS" "$ROOT/scripts/notarize.sh"
DMG="$ROOT/build/release/$DMG_NAME"
[[ -f "$DMG" ]] || fail "notarize.sh didn't produce $DMG_NAME"
BUILT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT/build/release/export/BAKE.app/Contents/Info.plist")"
[[ "$BUILT" == "$BUILD" ]] || fail "the app's build is $BUILT, expected $BUILD"
BUILT_FEED="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$ROOT/build/release/export/BAKE.app/Contents/Info.plist")"
[[ "$BUILT_FEED" == "$FEED_URL" ]] || fail "the app's SUFeedURL is $BUILT_FEED, expected $FEED_URL"
SHA="$(shasum -a 256 "$DMG" | awk '{ print $1 }')"

step "Signing the update and writing the feed"
WORK="$ROOT/build/release/appcast-work"
rm -rf "$WORK" && mkdir -p "$WORK"
cp "$DMG" "$WORK/"
OLD_FEED="$SITE/${FEED_DIR}appcast.xml"
if [[ -f "$OLD_FEED" ]]; then cp "$OLD_FEED" "$WORK/appcast.xml"; fi
OLD_ITEMS="$($APPCAST count "$WORK/appcast.xml")"
"$SPARKLE_BIN/generate_appcast" --maximum-versions 0 --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    -o "$WORK/appcast.xml" "$WORK"
$APPCAST set-notes "$WORK/appcast.xml" --build "$BUILD" --url "$SITE_URL/${FEED_DIR}notes/$VERSION.html"
xmllint --noout "$WORK/appcast.xml"
$APPCAST check "$WORK/appcast.xml" --build "$BUILD" --version "$VERSION" --url "$DMG_URL" \
    --min-items "$((OLD_ITEMS + 1))" --min-system 26.0
"$SPARKLE_BIN/sign_update" --verify "$DMG" "$($APPCAST signature "$WORK/appcast.xml" --build "$BUILD")" \
    || fail "Sparkle's signature on the DMG doesn't verify"

NOTES_HTML="$WORK/$VERSION.html"
{
    printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
    printf '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
    printf '<title>BAKE %s</title><link rel="stylesheet" href="/style.css"></head>\n' "$VERSION"
    printf '<body><main class="notes"><h1>BAKE %s</h1>\n' "$VERSION"
    gh api markdown -f mode=gfm -f text="$(cat "$NOTES")"
    printf '\n</main></body></html>\n'
} > "$NOTES_HTML"

if [[ $DRY_RUN == 1 ]]; then
    PREVIEW="$ROOT/build/release/site-preview"
    mkdir -p "$PREVIEW/${FEED_DIR}notes"
    cp "$WORK/appcast.xml" "$PREVIEW/${FEED_DIR}appcast.xml"
    cp "$NOTES_HTML" "$PREVIEW/${FEED_DIR}notes/$VERSION.html"
    step "Dry run done: $DMG (version $VERSION, build $BUILD, SHA-256 $SHA); feed in $PREVIEW"
    exit 0
fi

step "Publishing the GitHub Release"
RELEASE_FLAGS=(--title "BAKE $VERSION" --notes-file "$NOTES" --target "$(git -C "$ROOT" rev-parse HEAD)")
if [[ $REHEARSAL == 1 ]]; then RELEASE_FLAGS+=(--prerelease); fi
gh release create "$TAG" "$DMG" -R "$REPO" "${RELEASE_FLAGS[@]}"
# The feed only goes live once the file it points to downloads, byte for byte.
DOWNLOADED="$WORK/downloaded.dmg"
curl -fsSL -o "$DOWNLOADED" "$DMG_URL" || fail "$DMG_URL doesn't download"
[[ "$(shasum -a 256 "$DOWNLOADED" | awk '{ print $1 }')" == "$SHA" ]] \
    || fail "the DMG on GitHub isn't this build's DMG; delete the release and run again"

step "Publishing the feed"
NEW_SIG="$($APPCAST signature "$WORK/appcast.xml" --build "$BUILD")"
if [[ -f "$OLD_FEED" && "$($APPCAST signature "$OLD_FEED" --build "$BUILD" 2>/dev/null)" == "$NEW_SIG" ]]; then
    echo "the feed already has build $BUILD with this signature"
else
    mkdir -p "$SITE/${FEED_DIR}notes"
    cp "$WORK/appcast.xml" "$SITE/${FEED_DIR}appcast.xml"
    cp "$NOTES_HTML" "$SITE/${FEED_DIR}notes/$VERSION.html"
    git -C "$SITE" add -- "${FEED_DIR}appcast.xml" "${FEED_DIR}notes/$VERSION.html"
    git -C "$SITE" commit -q -m "BAKE $VERSION (build $BUILD)" -- "${FEED_DIR}appcast.xml" "${FEED_DIR}notes/$VERSION.html"
    git -C "$SITE" push -q origin main
fi

step "Done: BAKE $VERSION (build $BUILD)"
echo "DMG:     $DMG"
echo "SHA-256: $SHA"
echo "Next:    upload this DMG to the Gumroad product (https://bassdaddy.gumroad.com/l/syqlk)."
