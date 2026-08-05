# M3 Agent Handoff — Uttr

## What is Uttr

A native Swift 6 / SwiftUI macOS menu-bar-only, hold-to-talk, local-first dictation app for Apple Silicon. Audio never leaves the Mac.

## Governing Documents (read these first, they are the contract)

1. `UTTR_AGENT_BUILD_SPEC.md (provide as attachment)` — Full product spec with milestones, locked decisions, test requirements
2. `UTTR_MASTER_AGENT_OPERATING_PROMPT.md (provide as attachment)` — Agent operating rules, work style, truthfulness rules, validator packet template

## Repository

- Remote: https://github.com/prithvi-bommu/uttr (private)
- Clone fresh: `git clone https://github.com/prithvi-bommu/uttr.git`
- All work is on `main` — M0, M1, and M2 are merged

## What is built (M0–M2)

- **Project skeleton**: Xcode project with `PBXFileSystemSynchronizedRootGroup`, Swift 6 strict concurrency, arm64, macOS 15.0, App Sandbox disabled, `LSUIElement = YES`
- **State machine**: `DictationState` enum (idle, recording, transcribing, polishing, pasting, awaitingHotkey, blocked) + `AppState` with `handle(_ event: DictationEvent) -> Bool`
- **ConfigurationStore**: atomic JSON persistence to `~/Library/Application Support/Uttr/config.json`, 0700 dir / 0600 file permissions, `FileSystemProtocol` for testing
- **Settings**: 5-tab window (General, Transcription, Text Polish, Permissions, Privacy)
- **Onboarding**: 5-step first-run flow
- **PermissionService**: microphone (AVCaptureDevice), input monitoring (CGEvent test), accessibility (AXIsProcessTrusted)
- **EventTapHotkeyService**: CGEventTap on serial DispatchQueue, hold-to-talk, key-repeat suppression, escape cancel, Fn/Globe rejection, shortcut capture
- **AppEnvironment**: wiring layer connecting hotkey → AppState
- **99 tests** all passing
- **CI**: GitHub Actions on macos-15 with Xcode 16.4

## Key architecture decisions

- `@Observable` / `@MainActor` for state (not Combine)
- `FileSystemProtocol` abstraction for testable file I/O
- `PermissionChecking` protocol with `MockPermissionService` test double
- `HotkeyServiceProtocol` with `MockHotkeyService` test double
- API keys stored as plaintext in config.json (v1 decision, disclosed in UI)
- No Keychain, no accounts, no telemetry
- Bundle ID: `com.uttr.app`

## Stub files awaiting implementation

These exist in the repo but are empty/stub:
- `Uttr/Services/AudioRecorder.swift`
- `Uttr/Services/SpeechAnalyzerEngine.swift`
- `Uttr/Services/WhisperKitEngine.swift`
- `Uttr/Services/TranscriptionCoordinator.swift`
- `Uttr/Services/PasteService.swift`
- `Uttr/Services/ClipboardRestoreService.swift`
- `Uttr/Services/OpenAITextPolisher.swift`
- `Uttr/Services/AnthropicTextPolisher.swift`
- `Uttr/Services/TextPolisherFactory.swift`
- `Uttr/Services/LoginItemService.swift`

## Your task: M3

**IMPORTANT: Before implementing M3, the spec requires a technical spike first.**

### Required technical spike (before M3)

Create branch `spike/physical-macos-integration` and build minimal proof-of-concepts for:

1. Microphone authorization and `AVAudioEngine` in-memory capture
2. Quartz event tap behavior verification (already partially proven by M2, but validate on the CI runner's environment)
3. Synthetic Command-V posting into TextEdit after Accessibility permission
4. `SpeechAnalyzer`/`SpeechTranscriber` compile-time and runtime availability on the installed Xcode/macOS version
5. WhisperKit package API for local/in-memory transcription

Record results in `docs/DECISIONS.md`. Do not merge spike code into production.

### Then implement M3

Read the M3 scope from `UTTR_AGENT_BUILD_SPEC.md`. The target deliverable is:

`Control-Option-Space hold → local English speech → release → local transcript → paste into TextEdit`

This is the first usable private beta path.

## Workflow rules

- One milestone per PR. Branch naming: `feat/m3-short-description`
- Run `xcodebuild build` and `xcodebuild test` before opening PR
- Include a Validator Packet in the PR description (template in the operating prompt)
- Never merge your own PR — the owner merges after review
- Conventional Commit messages
- Update `CHANGELOG.md` under `Unreleased`
- Never claim platform behavior works unless tested on a physical Mac
- If an API is unavailable or doesn't match the spec, create a decision record — don't stub around it

## Build commands

```bash
xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug build
xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug test -destination 'platform=macOS,arch=arm64'
```
