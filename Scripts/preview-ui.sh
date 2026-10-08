#!/bin/bash
set -euo pipefail
mkdir -p build/Previews
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > build/preview-build.log 2>&1
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
xcrun simctl install "$PIVOT_SIMULATOR" build/DerivedData/Build/Products/Debug-iphonesimulator/Pivot.app
for PIVOT_SCREEN in today coach income settings tutoring launch income-warning income-red duplicates birthday workout-widget strength-ranks; do
  xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
  xcrun simctl launch "$PIVOT_SIMULATOR" app.pivot.personal --preview "--screen=$PIVOT_SCREEN"
  sleep 3
  xcrun simctl io "$PIVOT_SIMULATOR" screenshot "build/Previews/$PIVOT_SCREEN.png"
done
xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
sleep 1
xcrun simctl io "$PIVOT_SIMULATOR" screenshot "build/Previews/home-icon.png"

# A screenshot can look correct even when every touch is blocked. Exercise the
# real root refresh path with a deliberately slow background calendar import.
# Preserve the test result while exporting screenshots on failure as well.
PIVOT_UI_TEST_STATUS=0
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -destination "platform=iOS Simulator,id=$PIVOT_SIMULATOR" \
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO \
  -resultBundlePath build/interaction-tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test > build/interaction-tests.log 2>&1 || PIVOT_UI_TEST_STATUS=$?
if [ -d build/interaction-tests.xcresult ]; then
  xcrun xcresulttool export attachments --path build/interaction-tests.xcresult --output-path build/Previews/Interactions || {
    if [ "$PIVOT_UI_TEST_STATUS" -eq 0 ]; then PIVOT_UI_TEST_STATUS=1; fi
  }
fi
PIVOT_APP_DATA=$(xcrun simctl get_app_container "$PIVOT_SIMULATOR" app.pivot.personal data)
if [ -f "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" ]; then
  cp "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" build/Pivot-QA-report.pdf
fi
exit "$PIVOT_UI_TEST_STATUS"
