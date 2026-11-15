#!/bin/zsh
# Run all local package tests. Run from any folder.
set -euo pipefail
cd "${0:A:h}/.."
if [[ ! -f Packages/HandyKit/Package.swift ]]; then
  print -u2 "test.sh: missing required package: Packages/HandyKit"
  exit 1
fi
for pkg in Packages/*(N/); do
  if [[ ! -f "$pkg/Package.swift" ]]; then
    print -u2 "test.sh: missing Package.swift: $pkg"
    exit 1
  fi
  swift test --package-path "$pkg"
done
# UIKit layout tests need an available iOS Simulator runtime.
if xcrun simctl list runtimes -j | python3 -c '
import json, sys
runtimes = json.load(sys.stdin)["runtimes"]
sys.exit(not any(r.get("isAvailable", False) and r.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-") for r in runtimes))
'; then
  if [[ ! -d HandyIOS.xcodeproj ]]; then
    xcodegen generate --quiet
  fi
  xcodebuild test -project HandyIOS.xcodeproj -scheme HandyIOS \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -derivedDataPath build/Snapshots CODE_SIGNING_ALLOWED=NO \
    -only-testing:KeyboardLayoutTests -quiet
else
  print 'SKIP: KeyboardLayoutTests (no available iOS Simulator runtime).'
fi
