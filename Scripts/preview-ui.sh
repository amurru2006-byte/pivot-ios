#!/bin/bash
set -euo pipefail
mkdir -p build/Previews
xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/PreviewData CODE_SIGNING_ALLOWED=NO build > build/preview-build.log 2>&1
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
xcrun simctl install "$PIVOT_SIMULATOR" build/PreviewData/Build/Products/Debug-iphonesimulator/Pivot.app
for PIVOT_SCREEN in today income settings tutoring launch income-warning income-red duplicates birthday; do
  xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
  xcrun simctl launch "$PIVOT_SIMULATOR" app.pivot.personal --preview "--screen=$PIVOT_SCREEN"
  sleep 3
  xcrun simctl io "$PIVOT_SIMULATOR" screenshot "build/Previews/$PIVOT_SCREEN.png"
done
xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
sleep 1
xcrun simctl io "$PIVOT_SIMULATOR" screenshot "build/Previews/home-icon.png"
