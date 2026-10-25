#!/bin/zsh
# Runs the UI tour on a connected device and exports its screenshots.
#   tools/ui-test.sh [device-udid]   (default: the XS Max test phone)
set -e
DIR=${0:A:h}; ROOT=$DIR/..
UDID=${1:-00008020-001D4D841E02002E}
STAMP=$(date +%Y%m%d-%H%M%S)
RESULT=$DIR/.results/$STAMP.xcresult
OUT=$DIR/screens/$STAMP
mkdir -p $DIR/.results $OUT
cd $ROOT
xcodegen generate >/dev/null
xcodebuild test -project BeautyCam.xcodeproj -scheme BeautyCam -destination "platform=iOS,id=$UDID" \
  -derivedDataPath build -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  -resultBundlePath $RESULT 2>&1 | grep -E "error:|Test Case|TEST|\*\*" || true
RAW=$DIR/.results/$STAMP-raw
xcrun xcresulttool export attachments --path $RESULT --output-path $RAW >/dev/null
# Keep only the step screenshots, renamed to their step names (e.g. 01-camera.png).
python3 - "$RAW" "$OUT" <<'PY'
import json, shutil, sys, re
raw, out = sys.argv[1], sys.argv[2]
for test in json.load(open(f"{raw}/manifest.json")):
    for a in test.get("attachments", []):
        m = re.match(r"(\d\d-[^_]+)_", a.get("suggestedHumanReadableName", ""))
        if m and a["exportedFileName"].endswith(".png"):
            shutil.copy(f"{raw}/{a['exportedFileName']}", f"{out}/{m.group(1)}.png")
PY
echo "screens: $OUT"; ls $OUT
