# handyIOS

Local-only dictation for iOS with the NVIDIA Parakeet speech model.

- A custom keyboard with a mic key. The companion app records and transcribes on the device.
- The app downloads the model once. Audio and text never leave the phone.
- Recording stops by itself after a short silence.

Status: early development. See the `v1` milestone for the plan.

## Build

Needs Xcode 26 or later and XcodeGen (`brew install xcodegen`).

```sh
./scripts/build.sh   # build for the iOS Simulator
./scripts/test.sh    # run the test suite
```
