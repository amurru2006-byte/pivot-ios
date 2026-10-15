#!/bin/bash
set -euo pipefail
PIVOT_UI_ONLY_TESTING=${PIVOT_UI_ONLY_TESTING:-}
PIVOT_UI_TEST_FILTER=()
PIVOT_PREVIEW_OUTPUT=build/Previews
PIVOT_UI_BUILD_LOG=build/preview-build.log
PIVOT_UI_LOG=build/interaction-tests.log
PIVOT_UI_RESULT=build/interaction-tests.xcresult
PIVOT_SIM_ENTITLEMENTS=build/simulator-entitlements.plist
case "$PIVOT_UI_ONLY_TESTING" in
  '') ;;
  PivotUITests/OnlineCoachSetupInteractionTests)
    PIVOT_UI_TEST_FILTER=("-only-testing:$PIVOT_UI_ONLY_TESTING")
    PIVOT_PREVIEW_OUTPUT=build/Previews/QRPreflight
    PIVOT_UI_BUILD_LOG=build/qr-preflight-build.log
    PIVOT_UI_LOG=build/qr-preflight-tests.log
    PIVOT_UI_RESULT=build/qr-preflight-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/qr-preflight-simulator-entitlements.plist
    ;;
  *) printf '%s\n' 'Unsupported PIVOT_UI_ONLY_TESTING; refusing to skip arbitrary regressions.' >&2; exit 2 ;;
esac
mkdir -p "$PIVOT_PREVIEW_OUTPUT"
# The simulator still uses the real Security framework for the protected-QR
# persistence test. Unsigned builds have no private Keychain access group.
# Use a deliberately synthetic, per-bundle identity only in these Debug
# simulator invocations; the iPhone Release packaging remains unchanged.
PIVOT_SIM_SIGNING=(
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
  "CODE_SIGN_ENTITLEMENTS=$PWD/Scripts/simulator-keychain.entitlements"
)
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData "${PIVOT_SIM_SIGNING[@]}" build > "$PIVOT_UI_BUILD_LOG" 2>&1
PIVOT_SIM_APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Pivot.app
codesign --verify --deep --strict "$PIVOT_SIM_APP"
codesign --display --entitlements :- "$PIVOT_SIM_APP" > "$PIVOT_SIM_ENTITLEMENTS" 2>/dev/null
python3 - "$PIVOT_SIM_ENTITLEMENTS" <<'PY'
import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open('rb') as source:
    entitlements = plistlib.load(source)
with Path('build/DerivedData/Build/Products/Debug-iphonesimulator/Pivot.app/Info.plist').open('rb') as source:
    bundle = plistlib.load(source)['CFBundleIdentifier']
expected = 'PIVOTSIMQA.' + bundle
assert entitlements.get('application-identifier') == expected, 'Simulator QA app identity missing'
assert entitlements.get('keychain-access-groups') == [expected], 'Simulator QA private Keychain group missing'
assert entitlements.get('get-task-allow') is True, 'Simulator debugging entitlement missing'
assert entitlements.get('com.apple.developer.healthkit') is True
assert entitlements.get('com.apple.developer.healthkit.background-delivery') is True
print('Simulator QA Keychain identity verified (synthetic; not iPhone signing).')
PY
xcrun simctl list devices available -j > build/devices.json
PIVOT_SIMULATOR=$(python3 - <<'PY'
import json
with open('build/devices.json') as f: data=json.load(f)
phones=[x for values in data['devices'].values() for x in values if x['name'].startswith('iPhone') and x['isAvailable']]
preferred=next((x for x in phones if x['name']=='iPhone 16'), phones[0])
print(preferred['udid'])
PY
)
xcrun simctl boot "$PIVOT_SIMULATOR" || true
xcrun simctl bootstatus "$PIVOT_SIMULATOR" -b
xcrun simctl status_bar "$PIVOT_SIMULATOR" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$PIVOT_SIMULATOR" "$PIVOT_SIM_APP"
if [ -z "$PIVOT_UI_ONLY_TESTING" ]; then
  for PIVOT_SCREEN in today coach income settings tutoring launch income-warning income-red duplicates birthday workout-widget strength-ranks; do
    xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
    xcrun simctl launch "$PIVOT_SIMULATOR" app.pivot.personal --preview "--screen=$PIVOT_SCREEN"
    sleep 3
    xcrun simctl io "$PIVOT_SIMULATOR" screenshot "$PIVOT_PREVIEW_OUTPUT/$PIVOT_SCREEN.png"
  done
  xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
  sleep 1
  xcrun simctl io "$PIVOT_SIMULATOR" screenshot "$PIVOT_PREVIEW_OUTPUT/home-icon.png"
fi

# A screenshot can look correct even when every touch is blocked. Exercise the
# real root refresh path with a deliberately slow background calendar import.
# Preserve the test result while exporting screenshots on failure as well.
PIVOT_UI_TEST_STATUS=0
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -destination "platform=iOS Simulator,id=$PIVOT_SIMULATOR" \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -resultBundlePath "$PIVOT_UI_RESULT" "${PIVOT_UI_TEST_FILTER[@]}" \
  "${PIVOT_SIM_SIGNING[@]}" test > "$PIVOT_UI_LOG" 2>&1 || PIVOT_UI_TEST_STATUS=$?
if [ -d "$PIVOT_UI_RESULT" ]; then
  xcrun xcresulttool export attachments --path "$PIVOT_UI_RESULT" --output-path "$PIVOT_PREVIEW_OUTPUT/Interactions" || {
    if [ "$PIVOT_UI_TEST_STATUS" -eq 0 ]; then PIVOT_UI_TEST_STATUS=1; fi
  }
fi
PIVOT_APP_DATA=$(xcrun simctl get_app_container "$PIVOT_SIMULATOR" app.pivot.personal data)
if [ -z "$PIVOT_UI_ONLY_TESTING" ] && [ -f "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" ]; then
  cp "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" build/Pivot-QA-report.pdf
fi
if [ -z "$PIVOT_UI_ONLY_TESTING" ] && [ -f "$PIVOT_APP_DATA/Documents/Pivot-QA-finalization.pdf" ]; then
  cp "$PIVOT_APP_DATA/Documents/Pivot-QA-finalization.pdf" build/Pivot-QA-finalization.pdf
fi
exit "$PIVOT_UI_TEST_STATUS"
