#!/bin/bash
set -euo pipefail
# Invoked only after the complete Core/gateway/Release/UI regression succeeds.
PIVOT_APP=build/DerivedData/Build/Products/Release-iphoneos/Pivot.app
test -d "$PIVOT_APP"
for PIVOT_FRAMEWORK in "$PIVOT_APP"/Frameworks/*.framework; do
  if [ -d "$PIVOT_FRAMEWORK" ]; then codesign --force --sign - "$PIVOT_FRAMEWORK"; fi
done
codesign --force --sign - "$PIVOT_APP/PlugIns/PivotWorkoutWidget.appex"
codesign --force --sign - --generate-entitlement-der --entitlements Pivot/Pivot.entitlements "$PIVOT_APP"
codesign --display --entitlements :- "$PIVOT_APP" > build/packaged-entitlements.plist 2>/dev/null
codesign --verify --deep --strict "$PIVOT_APP"
python3 - <<'PY'
import plistlib
from pathlib import Path
with Path('build/packaged-entitlements.plist').open('rb') as source:
    entitlements = plistlib.load(source)
assert entitlements.get('com.apple.developer.healthkit') is True
assert entitlements.get('com.apple.developer.healthkit.background-delivery') is True
app = Path('build/DerivedData/Build/Products/Release-iphoneos/Pivot.app')
with (app / 'Info.plist').open('rb') as source:
    info = plistlib.load(source)
assert info['CFBundleShortVersionString'] == '0.8.0'
assert info['CFBundleVersion'] == '22'
assert info['CFBundleIdentifier'] == 'app.pivot.personal'
assert 'pivot' in [scheme for entry in info['CFBundleURLTypes'] for scheme in entry['CFBundleURLSchemes']]
with (app / 'PlugIns/PivotWorkoutWidget.appex/Info.plist').open('rb') as source:
    widget = plistlib.load(source)
assert widget['CFBundleShortVersionString'] == '0.8.0' and widget['CFBundleVersion'] == '22'
PY
mkdir -p build/Package/Payload
cp -R "$PIVOT_APP" build/Package/Payload/
(cd build/Package && zip -qr ../Pivot-0.8.0.ipa Payload)
python3 - <<'PY'
import hashlib, json, subprocess
from pathlib import Path
ipa = Path('build/Pivot-0.8.0.ipa')
manifest = dict(version='0.8.0', build=22, candidate=True,
    commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    file=ipa.name, bytes=ipa.stat().st_size, sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
    healthKit=True, healthKitBackgroundDelivery=True,
    credentialsBundled=False, calendarChangesRequireConfirmation=True)
Path('build/Pivot-0.8.0-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
