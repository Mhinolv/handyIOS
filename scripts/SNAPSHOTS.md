# Visual QA screenshots

Run `./scripts/snapshot.sh <out-dir>` on a Mac with Xcode, XcodeGen, and the iOS 27.2 simulator runtime.
The script uses the existing iPhone 18 Pro simulator. It builds Debug, boots the device, and installs the app.
It captures each state in light and dark. Each file uses `<state>-<appearance>.png`.
The script stops on a build, launch, or capture error. Use an empty output folder for each run.

States:

- setup
- model-not-downloaded, model-downloading, model-failed, model-ready
- listening, transcribing, text-ready, recovery
- last-result, silence-settings, replacements, licenses
- keyboard-idle, keyboard-opening, keyboard-listening, keyboard-inserted, keyboard-full-access-off, keyboard-abc

The DEBUG argument `-HandySnapshotState <state>` selects an inert screen.
The host uses the app views and the keyboard controller with fake HandyKit data.
It does not start audio, load models, use shared session storage, or download files.
Release excludes the host, argument switch, fixtures, and app copies of keyboard sources.

Check all 38 PNGs for clipped text, missing controls, and appearance errors.
The keyboard host shows the extension view inside the app. It does not test host-app handoff or text insertion.
