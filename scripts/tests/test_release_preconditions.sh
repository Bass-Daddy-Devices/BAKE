#!/bin/bash
# release.sh must stop before building when a release isn't ready. Runs on a throwaway clone of HEAD.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
git clone -q "$ROOT" "$WORK/BAKE"
cd "$WORK/BAKE"

expect_failure() {
    local message="$1"; shift
    local output
    if output="$("$@" 2>&1)"; then
        echo "FAIL: expected \"$message\", but it succeeded"; exit 1
    fi
    if ! grep -qF "$message" <<<"$output"; then
        echo "FAIL: expected \"$message\", got:"; echo "$output"; exit 1
    fi
    echo "ok: $message"
}

VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' BAKE/BAKE.xcodeproj/project.pbxproj | sort -u)"

echo scratch > scratch.txt
expect_failure "the working tree isn't clean" scripts/release.sh 9.9.9 --dry-run
rm scratch.txt

expect_failure "MARKETING_VERSION is" scripts/release.sh 9.9.9 --dry-run

sed -i '' "s/MARKETING_VERSION = $VERSION;/MARKETING_VERSION = 7.7.7;/" BAKE/BAKE.xcodeproj/project.pbxproj
git -c user.name=test -c user.email=test@example.com commit -qam "test: 7.7.7"
expect_failure "release-notes/7.7.7.md is missing" scripts/release.sh 7.7.7 --dry-run

echo "all release precondition checks pass"
