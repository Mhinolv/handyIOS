#!/bin/zsh
# Build both targets for the iOS Simulator. Run from any folder.
set -euo pipefail
cd "${0:A:h}/.."
for required in project.yml App/HandyIOSApp.swift Keyboard/KeyboardViewController.swift Packages/HandyKit/Package.swift; do
  if [[ ! -f "$required" ]]; then
    print -u2 "build.sh: missing required file: $required"
    exit 1
  fi
done
xcodegen generate --quiet
# Check the generated project, so a removed target cannot produce a false pass.
targets=$(xcodebuild -list -json -project HandyIOS.xcodeproj)
print -r -- "$targets" | python3 -c '
import json, sys
project = json.load(sys.stdin)["project"]
missing = {"HandyIOS", "HandyKeyboard"} - set(project["targets"])
if missing or "HandyIOS" not in project["schemes"]:
    sys.exit("build.sh: missing required targets or HandyIOS scheme: " + str(sorted(missing)))
'
xcodebuild -project HandyIOS.xcodeproj -scheme HandyIOS   -destination 'generic/platform=iOS Simulator'   -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet build
