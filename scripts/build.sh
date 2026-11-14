#!/bin/zsh
# Build every target for the iOS Simulator. Run from any folder.
# The scaffold issue replaces the body below with the real build.
set -e
cd "${0:A:h}/.."
if [[ ! -f project.yml ]]; then
  echo "build.sh: no project.yml yet (scaffold issue not merged). Nothing to build."
  exit 0
fi
xcodegen generate --quiet
xcodebuild -project HandyIOS.xcodeproj -scheme HandyIOS -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData -quiet build
