# AGENTS.md: handyIOS

## Product Overview

handyIOS is a small iOS companion app for local dictation. It downloads the NVIDIA Parakeet speech model to the device and uses it instead of iOS native dictation. All audio and text stay on the device.

- User: the owner, on a personal iPhone. Public repo, personal account `Mhinolv`.
- Dictation surface (owner decision 2026-11-14): a custom keyboard with a mic key. The keyboard opens the app. The app records in the background, transcribes with Parakeet and sends the text back to the keyboard through a shared App Group. The keyboard inserts the text.
- Owner request: stop the recording automatically when the user does not speak for a short time (silence auto-stop).
- Borrow local-only features from desktop tools such as Handy (cjpais/handy). No cloud ASR, no accounts, no analytics.
- Apple: paid developer account. The team ID goes into `project.yml` as a setting, never a secret.

## Architecture Map (planned; the scaffold issue makes it real)

| Area | Files |
|---|---|
| Project definition (XcodeGen) | `project.yml` (generates `HandyIOS.xcodeproj`, not in git) |
| App target (SwiftUI) | `App/` |
| Keyboard extension | `Keyboard/` |
| Core logic, testable on macOS | `Packages/HandyKit/` (silence detection, session state, App Group messages, model download state) |
| ASR wrapper | Behind a protocol in HandyKit. Real engine: FluidAudio (Parakeet TDT CoreML). Tests use a fake. |
| Build and test | `scripts/build.sh`, `scripts/test.sh` |

Rules:
- Keep logic in `HandyKit` behind protocols. Views stay thin.
- Never put model files in git. The app downloads them at run time.
- No network calls except the model download.
- Keyboard extension memory is limited (about 50 to 70 MB). Never load the model in the keyboard.

## Build and test

- Build: `./scripts/build.sh` (XcodeGen, then `xcodebuild` for the iOS Simulator).
- Full suite: `./scripts/test.sh` (`swift test` for each package in `Packages/`).
- CI is light until the first published release (owner decision 2026-11-14). PRs run only the PR-template check. The build-and-test workflow runs only by hand. The local build and full suite are the merge gate.
- Keep tests fast. Use fakes for audio, ASR, the file system and the clock.
- SwiftUI `#Preview` macros cannot run in the Codex sandbox. Use `PreviewProvider`.

## Team Roadmap Workflow (multi-agent, GitHub)

A multi-agent team works the release milestone in GitHub (`Mhinolv/handyIOS`). GitHub Issues are the single source of truth. Every change ships as a pull request into `main`. Everyone writes in ASD-STE100 Simplified Technical English with hard length budgets (see the product-team skill, `~/.claude/writing_standard.md`). Roles:

| Role | Responsibility | Output |
|---|---|---|
| Orchestrator | Supervises, prioritizes, creates issue branches, commits/pushes for the engineer, opens PRs, final approver | Merges PRs, closes issues |
| Product Research | Competitor analysis and gap finding | `research.md` |
| Product Manager | Turns gaps/requests into issues (Problem, Scope & Boundaries, Acceptance criteria) | Issues + `**PM review**` comments |
| UI/UX | `## Design notes` section of each issue | Body section + `**UX notes**` comment |
| Engineer | Implements one issue on its linked branch; regression test first for bugs | Changes + `PR BODY` / `COMMIT FILES` blocks |
| QA | Reviews the PR against the issue's acceptance criteria, design notes and owner decisions | Inline review comments + `QA RESULT: PASS/FAIL` PR comment |

Issue flow labels (exactly one at a time): `needs-pm` → `needs-ux` → `ready` → `in-progress` → `in-review` → (`needs-owner-check`) → closed. Also: `bug`/`feature`, `P0`–`P3`, `owner-request`, `redesign`, `blocked`; PR labels `qa-pass`/`qa-fail`.

Rules:
- Issue bodies use the sections `## Problem / Request`, `## Scope & Boundaries`, `## Acceptance criteria`, `## Design notes`, `## Owner decisions`. Edit one section at a time; never drop the others.
- Product-owner decisions are posted as `**Owner decision:** …` comments and mirrored in `## Owner decisions`; they override earlier wording.
- One issue = one branch (`<n>-<slug>`, created with `gh issue develop`) = one PR into `main`. Commits: `#<n>: <summary>`. Stage only the files changed for that issue. Never `git add -A`. Never commit to main.
- PRs must satisfy the PR template (What changed / Issue / How it was tested / Risk and rollback). `Refs #n` instead of `Closes #n` while the owner still has to check it.
- The PR-template check must be green, and the local build and full suite must pass, before merge.
- The Engineer does not commit, push, open PRs or close issues. QA does not modify source. Only the Orchestrator merges PRs and closes issues.
- For this milestone, **QA PASS + green checks + Orchestrator approval replaces the manual user-test gate**, except issues labelled `needs-owner-check` (on-device items: microphone, keyboard, model download).
- No agent may use browser/Chrome/computer-use/GUI automation tools.
