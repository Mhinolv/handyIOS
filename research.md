# handyIOS v1 research

Research date: 2026-11-14. Run: `research-1`.

## Executive Summary

Build a small, local dictation app with a keyboard extension and silence auto-stop. Keep the model and microphone in the app.

Use FluidAudio with Parakeet TDT 0.6B v3 for the first model. It supports iOS 17+ and 25 European languages. [S8–S11]

Validate the keyboard handoff before substantial model work. Current Wispr documentation requires manual return when automatic return fails. [S15]

Apple does not document keyboard support for `NSExtensionContext.open`. App Review rule 4.4.1 also restricts app launches from keyboards. [S14, S16]

Preserve the owner's keyboard design, but treat its launch path as an unresolved device and distribution constraint. Do not promise automatic return.

Propose a two-second silence delay, adjustable from one to five seconds, plus Off. This is a product proposal, not a verified competitor default.

The repo has no app code. The 12 features below form a build order. Open-issue deduplication remains unverified because GitHub access failed.

## Competitors

Prices reflect the cited pages on the research date. Store prices can differ. Weaknesses compare each product with our intended workflow.

| Product | Platform and price | Target user | Standout local features | Weakness or boundary |
|---|---|---|---|---|
| Handy [S1] | macOS, Windows, Linux. Free, MIT source. | People who need simple desktop dictation. | Local Parakeet/Whisper, Silero VAD, shortcut control, direct text insertion. | Desktop reference, not an iOS keyboard. Silence filtering does not prove auto-stop. |
| Wispr Flow [S2, S15, S18] | iOS, Android, macOS, Windows. Free tier. Pro $15/month or $12/month annually. | People who want text in many apps. | Keyboard controls, dictionary and snippets. Dictation needs a network connection. | Cloud ASR conflicts with our local-only requirement. Current iOS return behavior has limits. |
| Superwhisper [S3] | iOS, Android, macOS, Windows. Free tier. Pro $8.49/month, $84.99/year, or $249.99 lifetime online. | Frequent dictation users. | iPhone model downloads include Parakeet and Whisper. Custom vocabulary and keyboard input. | Local ASR does not establish that every AI mode is local. More options than our narrow v1 needs. |
| VoiceInk [S4] | Mac. Website also advertises iOS. Current price unverified. | Writers, students and developers. | Local ASR, custom words and exact phrase replacement on the documented Mac product. | iOS feature parity and price unverified. Do not assume all text enhancement stays local. |
| Aiko [S5] | macOS, iOS, visionOS. $24 once, with a trial. | People who transcribe audio files or voice notes. | Local Whisper, file transcription and Shortcuts. | The reviewed page does not establish an iOS dictation keyboard. |
| MacWhisper [S6] | macOS. Free tier, Pro €64 once. | People with interviews, files and meetings. | Local ASR, transcript editor, export and desktop dictation. | Mac workflow. Cloud model options require care for local-only use. |
| Whisper Notes [S7] | iPhone, iPad, Mac App Store: $7.99 once. Direct Mac version: $14 once. | People who need private voice notes. | Offline transcription, file import, speaker labels and iOS Shortcuts. | Website documents voice input across apps for Mac, not an iOS keyboard. |
| Muesli iOS [S12] | iOS 17+. MIT source, early TestFlight. Retail price unverified. | People who want local dictation and meeting notes. | FluidAudio Parakeet, App Group handoff, keyboard insertion and session mode. | Early distribution. Optional cloud summaries and telemetry scope need review before code reuse. |

Muesli is the closest architectural reference found. Its README describes the requested keyboard-to-app-to-keyboard path. This is source evidence, not a device test. [S12]

Borrow local controls, model downloads and explicit status. Exclude cloud cleanup, accounts, analytics, summaries and transcript sync from v1.

## Feature Matrix

Y = documented. O = optional local mode. — = not applicable to the documented platform. U = unverified.

| Product | Local ASR | iOS keyboard | Parakeet | Local file transcription | Vocabulary or replacements | Silence auto-stop |
|---|---|---|---|---|---|---|
| Handy | Y | — | Y | U | Y | U |
| Wispr Flow | No | Y | U | U | Y | U |
| Superwhisper | O | Y | Y on iPhone | Y | Y | U |
| VoiceInk | Y on Mac | U | Y on Mac | U | Y on Mac | U |
| Aiko | Y | U | U | Y | U | U |
| MacWhisper | O | — | U | Y | U | U |
| Whisper Notes | Y | U | Y on Mac | Y | U | U |
| Muesli iOS | Y | Y | Y | U | U | U |
| handyIOS today | No code | No code | Planned | Out of scope | No code | Owner request |

Sources: competitor rows use [S1–S7, S12]. “U” means the reviewed sources do not prove the capability or its absence.

## Gap Analysis

### Repository evidence

- `git ls-files` lists docs, CI files and two scripts. It lists no `App/`, `Keyboard/`, `Packages/`, or `project.yml`.
- `rg --files -g '*.swift'` found no Swift source.
- A source search for `Parakeet|AVAudio|Silence|AppGroup` found no Swift implementation.
- `scripts/build.sh` exits successfully when `project.yml` is absent. It is a scaffold placeholder, not build evidence.
- `scripts/test.sh` reports no packages when none exist. It is not test evidence.
- No release or review document was present beyond the PR template and CI files.
- The role brief identifies a greenfield product. Every proposed implementation is absent from the inspected source.

The authenticated issue read failed: no token for `Mhinolv`, followed by an API connection error. The public issue page also failed to load.

No verified issue numbers are available. Main or PM must compare this list with open issues before ticket creation. Exclude duplicates and cite their numbers.

### Parakeet on iOS

| Topic | Verified evidence | v1 consequence |
|---|---|---|
| SDK | FluidAudio uses Swift and Core ML. Its package declares iOS 17 and Swift tools 6.0. [S8] | Pin a tested release or commit. Keep its implementation behind the HandyKit ASR protocol. |
| Model | TDT v2 and v3 have 0.6 billion parameters. v2 is English-only. v3 covers 25 European languages. [S9–S11] | Start with v3. Defer the model chooser. |
| Input | v3 expects 16 kHz mono Float32 PCM. [S9] | Convert microphone audio in the app. |
| Download | FluidInference hosts Core ML bundles and vocabulary files on Hugging Face. [S9, S10] | Download assets at runtime. Pin the model revision and validate each required file. |
| Size | Repository totals are 3.59 GB for v3 and 2.58 GB for v2. Both contain alternative artifacts. [S10] | These totals are not the app download size. Exact selected asset size remains unverified. |
| Memory | The v2 card reports about 800 MB peak memory. It does not establish a supported iPhone memory budget. [S10] | Measure cold load and peak memory on the owner's phone. Keep the model out of the keyboard. |
| Speed | The v3 card reports about 110 times real-time throughput on an M4 Pro. [S9] | Do not convert this desktop result into an iPhone latency promise. |
| Batch versus stream | TDT v2/v3 use batch or overlapping windows. FluidAudio lists separate cache-aware models for true stream output. [S11] | Finish short dictation first, then transcribe. Defer live partial text. |
| VAD | FluidAudio provides Silero Core ML probabilities, stream state and speech events. [S13] | VAD can run during capture even when ASR runs after Stop. |
| License | FluidAudio is Apache-2.0. NVIDIA v3 metadata is CC-BY-4.0. The converted v3 card conflicts with itself. [S8, S9] | Keep SDK and model notices separate. Verify the pinned model license and attribution before distribution. |

The v3 language list follows. [S9]

- Bulgarian, Croatian, Czech, Danish, Dutch, English, Estonian, Finnish and French.
- German, Greek, Hungarian, Italian, Latvian, Lithuanian, Maltese and Polish.
- Portuguese, Romanian, Russian, Slovak, Slovenian, Spanish, Swedish and Ukrainian.

The current SDK catalog includes newer variants. That does not change the owner's v2/v3 brief. Do not select a moving default without an explicit model version. [S11]

### Keyboard handoff and current iOS limits

1. The keyboard creates a request ID and timestamp in the App Group.
2. Its mic key requests the companion app launch through a validated path.
3. The foreground app checks the model and microphone permission, then starts audio capture.
4. The user returns to the host app. Show manual return instructions when necessary.
5. The app captures audio in the background, then stops on silence or a user command.
6. The app transcribes locally and saves a result for that request ID.
7. The keyboard reads the result and inserts it through `textDocumentProxy` when the user returns.

This sequence is a proposed implementation. Muesli documents the shared request and result approach. Wispr documents the foreground microphone start and manual return fallback. [S12, S15]

Apple's archived keyboard guide denies microphone access to the extension. It requires open access for a shared container. [S14]

Thus, Full Access serves local App Group exchange here. It does not authorize this product to transmit audio, text or key presses.

Secure fields, phone-pad fields and apps that reject custom keyboards can hide the extension. Provide the globe key and explain these limits. [S14]

`NSExtensionContext.open` documents Today and iMessage support, not keyboard support. A callable API alone does not prove a supported launch path. [S16]

Do not treat responder-chain tricks or private host-app identifiers as a stable solution. The exact launch implementation remains unverified on the owner's iOS version.

Wispr's November 13 documentation describes manual return when it cannot identify a route back. Automatic return is therefore not a reliable acceptance criterion. [S15]

Apple permits continued audio capture with the `audio` background mode and microphone permission. Calls and alarms can interrupt the session. [S17]

After capture stops, background ASR completion still needs a device test. A finite background task can expire. Save an explicit retry state if completion fails.

The repo's 50–70 MB keyboard estimate is a planning constraint, not a verified fixed Apple limit. Measure extension memory separately.

App Review rule 4.4.1 requires keyboard input, a next-keyboard method and useful function without Full Access. It restricts launches beyond Settings. [S19]

Plan a small manual keyboard fallback. Record the containing-app launch question for review. Competitor availability does not prove approval for our implementation.

### Silence auto-stop

Silero detects speech probability. RMS measures signal energy. RMS alone cannot reliably distinguish a fan from speech. This is an engineering inference.

Use VAD for the stop decision and RMS for a level meter. Keep the decision logic independent of the audio engine.

FluidAudio documents a 0.75-second segment silence default. Its example uses 0.4 seconds. These values end speech segments, not an entire dictation session. [S13]

A verified common competitor auto-stop default was not found. Do not describe two seconds as an industry standard.

Proposed product settings:

| Setting | Proposed behavior |
|---|---|
| End-of-speech delay | Default 2 seconds. Choices: 1, 2, 3, 4, 5 seconds, or Off. |
| Initial silence | Stop after 10 seconds without speech. Show “No speech detected.” |
| Timer start | Start after the microphone is ready, not during model load or app transition. |
| Brief pause | Reset the silence timer when speech resumes. |
| Maximum session | Cap v1 at 60 seconds. Preserve captured speech at the cap. |
| Stop reason | Distinguish silence, user Stop, no speech, interruption and duration cap. |
| Model failure | Show the VAD error. Keep manual Stop available. Do not silently substitute an RMS threshold. |

The delay should measure time since the last speech sample. Avoid adding the SDK segment delay twice.

Auto-stop must release the microphone. Do not keep an idle audio session active merely to avoid the next app switch.

Test soft speech, fans, short pauses, Bluetooth routes and interrupted capture on a phone. Use fake probabilities and a fake clock for unit tests.

## Recommended Features

Numbers are proposal order, not GitHub issue numbers. Sizes: S = small, M = medium. Each item is one focused PR.

Every item fits one engineer and needs no backend or account. All paths below are proposed new files unless already listed in repository evidence.

1. **Project scaffold — P1, M.**
   Problem: no app target or testable core exists. Reference: Muesli's separate app, keyboard and shared code. [S12]
   Behavior: create XcodeGen `project.yml`, App and Keyboard targets, HandyKit, App Group entitlements and real build/test scripts.
   Files: `project.yml`, `App/`, `Keyboard/`, `Packages/HandyKit/`, `scripts/build.sh`, `scripts/test.sh`.
   Check: build both targets and run a package test. Fail when expected targets or packages are absent.
   Owner check: no. Device entitlement validation follows in item 3.

2. **Shared dictation protocol — P1, M.**
   Problem: separate processes need reliable requests and results. Reference: Muesli. [S12]
   Behavior: define request IDs, session states, atomic messages, expiry and result acknowledgement with fake storage tests.
   Files: `Packages/HandyKit/Sources/HandyKit/Session/`, `Packages/HandyKit/Tests/`.
   Check: reject stale results, duplicate requests and overlapping sessions. Expiry clears abandoned text.
   Depends on: 1. Owner check: no.

3. **Keyboard launch and fake-text return — P1, M.**
   Problem: the core iOS transition is unproven. References: Wispr and Muesli. [S12, S15]
   Behavior: add a mic key, globe key, shared request and fake transcript return. Include manual return instructions.
   Files: `Keyboard/KeyboardViewController.swift`, `App/Handoff/`, `project.yml`.
   Check: validate a supported launch route on the owner's current iOS. Reject private API dependence.
   Depends on: 2. Owner check: **yes — keyboard, App Group and host-app return**.
   Gate: report a blocked launch route before model integration. Do not claim acceptance from simulator results.

4. **Verified model download — P1, M.**
   Problem: the phone lacks the ASR and VAD assets. References: Handy and Superwhisper. [S1, S3]
   Behavior: download pinned v3 and Silero assets with progress, cancel, retry, file validation and available-space checks.
   Files: `App/Models/`, `App/ModelDownloadView.swift`, `Packages/HandyKit/Sources/HandyKit/ModelState/`.
   Check: fake partial download, corrupt file and disk-space failure. Show readiness only after validation.
   Depends on: 1. Owner check: **yes — real download, storage and offline readiness**.

5. **Local batch ASR adapter — P1, M.**
   Problem: no engine converts captured audio to text. References: Handy, Superwhisper and Muesli. [S1, S3, S12]
   Behavior: implement the HandyKit ASR protocol with FluidAudio v3. Include cleanup, cancellation and license notices.
   Files: `Packages/HandyKit/Sources/HandyKit/ASR/`, `App/Transcription/`, `App/ModelNoticesView.swift`.
   Check: use fake ASR in the package suite. Measure cold load, latency and memory with local sample audio.
   Depends on: 4. Owner check: **yes — actual iPhone model execution**.

6. **App microphone session — P1, M.**
   Problem: the keyboard cannot capture speech. References: Wispr and Muesli. [S12, S15]
   Behavior: request permission, capture bounded mono audio, show elapsed time and provide Stop and Cancel.
   Files: `App/Audio/`, `App/DictationView.swift`, `Packages/HandyKit/Sources/HandyKit/Audio/`, `project.yml`.
   Check: permission denial, no input, duration cap and resource release. Enable background audio only for active capture.
   Depends on: 2. Owner check: **yes — microphone and background capture**.

7. **Silence auto-stop — P1, M.**
   Problem: the owner must otherwise stop each session by hand. Reference: Handy's VAD, plus the explicit owner request. [S1]
   Behavior: connect Silero probabilities to a tested stop policy. Use the proposed delay choices, initial-silence limit and stop reasons.
   Files: `Packages/HandyKit/Sources/HandyKit/Silence/`, `App/Audio/SileroDetector.swift`, `App/SilenceSettingsView.swift`.
   Check: fake-clock boundary cases, resumed speech and noise. Release the mic when the policy stops capture.
   Depends on: 4, 6. Owner check: **yes — real speech and silence**.

8. **Real dictation delivery — P1, M.**
   Problem: the owner needs actual text at the cursor. References: Wispr, Superwhisper and Muesli. [S3, S12, S15]
   Behavior: connect capture, ASR and the shared protocol. Insert once during a live request and clear acknowledged results.
   Files: `App/DictationCoordinator.swift`, `Keyboard/ResultConsumer.swift`, `Packages/HandyKit/Tests/`.
   Check: duplicate delivery, changed focus and extension recreation. Require an explicit insert action after ambiguous recovery.
   Depends on: 3, 5, 7. Owner check: **yes — keyboard delivery in Notes, Messages and Safari**.

9. **Interruption and expiry recovery — P1, M.**
   Problem: calls, route changes and process loss can leave a session stuck. Reference: Whisper Notes interruption controls. [S7]
   Behavior: handle audio interruptions, missing app heartbeat and background task expiry. Show Retry or Discard without silent restart.
   Files: `App/Audio/InterruptionHandler.swift`, `App/DictationCoordinator.swift`, `Packages/HandyKit/Sources/HandyKit/Session/`.
   Check: fake events and cleanup tests. Keep recovery text brief and specific.
   Depends on: 8. Owner check: **yes — calls, lock screen and Bluetooth changes**.

10. **Keyboard setup and manual fallback — P1, M.**
    Problem: setup permissions are unclear and dictation cannot serve every field. References: Wispr and Superwhisper. [S3, S15]
    Behavior: add setup guidance, local privacy text and a basic letter/space/delete/return layout that works without Full Access.
    Files: `App/SetupView.swift`, `Keyboard/ManualKeyboardView.swift`, `Keyboard/KeyboardViewController.swift`.
    Check: denied permissions, globe switch, VoiceOver labels and secure-field fallback. Defer prediction, swipe input and autocorrection.
    Depends on: 3. Owner check: **yes — keyboard setup and permission states**.

11. **Last-result recovery — P2, S.**
    Problem: a lost text field can strand a valid transcript. References: Aiko and Whisper Notes copy workflows. [S5, S7]
    Behavior: show only the latest unclaimed result with Copy and Discard. Clear it after acknowledgement or a short documented expiry.
    Files: `App/LastResultView.swift`, `Packages/HandyKit/Sources/HandyKit/Session/`.
    Check: expiry and deletion with a fake clock. No permanent audio archive or automatic clipboard write.
    Depends on: 8. Owner check: no, unless the PR changes keyboard delivery.

12. **Local phrase replacements — P2, S.**
    Problem: repeated names and terms need the same correction. References: VoiceInk Smart Replace and Superwhisper vocabulary. [S3, S4]
    Behavior: apply explicit whole-phrase replacements after ASR. Keep rules local, ordered and reversible in settings.
    Files: `Packages/HandyKit/Sources/HandyKit/TextReplacement/`, `App/ReplacementSettingsView.swift`.
    Check: word boundaries, punctuation, case and overlapping rules. Do not claim model vocabulary adaptation.
    Depends on: 8. Owner check: no.

For each **yes**, apply `needs-owner-check`. QA can test the core with fakes, but cannot replace the listed device evidence.

Open decisions for main: confirm silence settings, the 60-second cap, transcript expiry and minimum supported phone. The keyboard architecture remains the owner's decision.

## Sources

All sources were reviewed on 2026-11-14. Vendor claims are not independent performance tests.

- **S1:** [Handy source and README](https://github.com/cjpais/Handy).
- **S2:** [Wispr pricing](https://wisprflow.ai/pricing). The page lists both a free tier and paid unlimited dictation. Exact free limits remain unclear.
- **S3:** [Superwhisper iPhone](https://superwhisper.com/voice-to-text-iphone), [iOS](https://superwhisper.com/ios), [model choices](https://superwhisper.com/models).
- **S4:** [VoiceInk product page](https://tryvoiceink.com/).
- **S5:** [Aiko product, price and FAQ](https://sindresorhus.com/aiko).
- **S6:** [MacWhisper product and price](https://www.macwhisper.com/).
- **S7:** [Whisper Notes product and price](https://whispernotes.app/).
- **S8:** [FluidAudio repository](https://github.com/FluidInference/FluidAudio), [package requirements](https://github.com/FluidInference/FluidAudio/blob/main/Package.swift).
- **S9:** [Core ML v3 card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml), [NVIDIA v3 card](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3).
- **S10:** [Core ML v2 card](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml), [v2 artifact tree](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v2-coreml/tree/main), [v3 artifact tree](https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/tree/main).
- **S11:** [FluidAudio model catalog](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Models.md).
- **S12:** [Muesli iOS source](https://github.com/Muesli-HQ/muesli-ios).
- **S13:** [FluidAudio VAD guide](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/VAD/GettingStarted.md), [segment defaults](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/VAD/Segmentation.md).
- **S14:** [Apple custom keyboard guide, archived](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html).
- **S15:** [Wispr current iOS handoff behavior](https://docs.wisprflow.ai/articles/6269634092-adapting-to-ios-26-4).
- **S16:** [Apple extension URL API](https://developer.apple.com/documentation/foundation/nsextensioncontext/open(_:completionhandler:)).
- **S17:** [Apple audio capture category and background behavior](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record).
- **S18:** [Wispr iOS network and audio failures](https://docs.wisprflow.ai/articles/9620169737-ios-missing-audio-chunks-during-unstable-internet).
- **S19:** [Apple App Review Guidelines, 4.4.1 and 2.5](https://developer.apple.com/app-store/review/guidelines/).
