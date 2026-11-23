#!/bin/bash
# Captures the user manual's screenshots: runs ManualScreenshotTests (Debug, -manualScene) and copies
# its attachments into BAKE_DOCS/manual/images/. Run from the repository root.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IMAGES="${BAKE_MANUAL_IMAGES:-$ROOT/BAKE_DOCS/manual/images}"
RESULT="$(mktemp -d)/shots.xcresult"
EXPORT="$(mktemp -d)"
mkdir -p "$IMAGES"

TEST_RUNNER_BAKE_MANUAL_SHOTS=1 xcodebuild test -workspace "$ROOT/BAKE_WORKSPACE.xcworkspace" -scheme BAKE -destination 'platform=macOS' \
    -derivedDataPath /tmp/bake-dd-manual -clonedSourcePackagesDirPath "$ROOT/build/packages" \
    -only-testing:BAKEUITests/ManualScreenshotTests -resultBundlePath "$RESULT" -quiet

xcrun xcresulttool export attachments --path "$RESULT" --output-path "$EXPORT"
# manifest.json maps exported files to the attachment names given in the test.
/usr/bin/python3 - "$EXPORT" "$IMAGES" <<'PY'
import json, os, re, shutil, sys
export, images = sys.argv[1], sys.argv[2]
copied = 0
for test in json.load(open(os.path.join(export, "manifest.json"))):
    for a in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]{36}$", "", os.path.splitext(a["suggestedHumanReadableName"])[0])
        shutil.copyfile(os.path.join(export, a["exportedFileName"]), os.path.join(images, name + ".png"))
        copied += 1
print(f"copied {copied} screenshots to {images}")
PY
