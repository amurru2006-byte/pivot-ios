#!/bin/bash
set -euo pipefail
PIVOT_XCODE=$(find /Applications -maxdepth 1 -name 'Xcode_*.app' | sort -V | tail -n 1)
if [ -n "$PIVOT_XCODE" ]; then sudo xcode-select -s "$PIVOT_XCODE/Contents/Developer"; fi
xcodebuild -version
brew install xcodegen
xcodegen generate
python3 - <<'PY'
import json
from pathlib import Path
approved = json.loads(Path('Scripts/trusted-macros.json').read_text())
assert len(approved) == 1
assert approved[0]['targetName'] == 'LLMMacrosImplementation'
assert approved[0]['packageIdentity'] == 'llm.swift'
assert ('revision: ' + approved[0]['fingerprint']) in Path('project.yml').read_text()
security = Path.home() / 'Library/org.swift.swiftpm/security'
security.mkdir(parents=True, exist_ok=True)
(security / 'macros.json').write_text(json.dumps(approved, indent=2))
PY
