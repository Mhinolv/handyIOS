#!/bin/zsh
# Save all Visual QA states without UI automation. Requires iOS 27.2.
set -euo pipefail
if (( $# != 1 )) || [[ -z "$1" ]]; then
  print -u2 'Usage: scripts/snapshot.sh <out-dir>'
  exit 1
fi
out=${1:A}
cd "${0:A:h}/.."
mkdir -p "$out"
udid=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
items=json.load(sys.stdin)["devices"].get("com.apple.CoreSimulator.SimRuntime.iOS-27-2", [])
match=next((d for d in items if d["name"] == "iPhone 18 Pro"), None)
if match is None: sys.exit("snapshot.sh: iPhone 18 Pro with iOS 27.2 is required")
print(match["udid"])
')
xcodegen generate --quiet
xcodebuild -project HandyIOS.xcodeproj -scheme HandyIOS -configuration Debug \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/Snapshots \
  CODE_SIGNING_ALLOWED=NO -quiet build
if ! xcrun simctl list devices booted -j | python3 -c 'import json,sys; sys.exit(not any(d["udid"] == sys.argv[1] for ds in json.load(sys.stdin)["devices"].values() for d in ds))' "$udid"; then
  xcrun simctl boot "$udid"
fi
xcrun simctl bootstatus "$udid" -b
bundle=com.mhinolv.handyios
xcrun simctl install "$udid" build/Snapshots/Build/Products/Debug-iphonesimulator/HandyIOS.app
trap 'xcrun simctl terminate "$udid" "$bundle" >/dev/null 2>&1 || true' EXIT
states=(setup model-not-downloaded model-downloading model-failed model-ready
  listening transcribing text-ready recovery last-result silence-settings replacements licenses
  keyboard-idle keyboard-launch-failed keyboard-transcribing keyboard-opening keyboard-listening keyboard-inserted keyboard-full-access-off keyboard-abc keyboard-shift keyboard-caps keyboard-numbers keyboard-symbols keyboard-search
  denied listening-last-10 no-speech vad-failure failed recovery-route recovery-expiry recovery-transcription
  setup-done replacements-empty replacements-edit last-result-copied keyboard-chip keyboard-recovery)
for state in $states; do
  for appearance in light dark; do
    xcrun simctl ui "$udid" appearance "$appearance"
    xcrun simctl launch --terminate-running-process "$udid" "$bundle" -HandySnapshotState "$state"
    sleep 3
    xcrun simctl io "$udid" screenshot "$out/$state-$appearance.png"
    xcrun simctl terminate "$udid" "$bundle"
  done
done
print "Saved $(( ${#states} * 2 )) screenshots to $out"
