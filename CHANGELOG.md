# Changelog

All notable changes to Uttr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Shortcut rebinding: `EventTapHotkeyService` parked its serial queue's thread inside `CFRunLoopRun()`, so `beginCapture`/`updateHotkey`/`cancelCapture` (dispatched with `queue.async`) never executed — Change Shortcut could never capture or apply a new combination. Decision logic is now a pure, lock-protected `HotkeyEventProcessor` mutated synchronously (ADR-008)
- Shortcut capture: rejected attempts (modifier-less key, reserved shortcut) now exit capture mode — previously `isCapturing` stayed set, leaving the tap swallowing all keyboard input
- Shortcut capture: the combination is sampled at key-down instead of key-up, so releasing the modifiers before the main key no longer falsely rejects the capture
- Reserved-shortcut table: Cmd-Shift-Space used Cmd-Option modifier bits (0x180000) instead of Cmd-Shift (0x120000)

### Added

- Bare 🌐/Fn (Globe) key supported as a hold-to-talk hotkey (ADR-008, owner-directed spec §0 amendment): detected via `flagsChanged`/`.maskSecondaryFn`, capturable in Change Shortcut, valid in settings with no modifiers. Requires System Settings → Keyboard → "Press 🌐 key to" set to "Do Nothing"; Fn+key combinations remain unsupported. Settings/README updated
- 19 `HotkeyEventProcessor` unit tests: hold-to-talk matching, repeat suppression, Escape, rebinding effect, capture happy/reject/reserved/stale paths, release-order tolerance, bare-Fn capture and hold-to-talk, and ADR-008 validation rules

### Added

- M4: Real cross-application paste — `PasteService` implements the exact spec sequence: snapshot plain-text clipboard → write transcript to `NSPasteboard.general` → 50 ms propagation wait → synthetic Command-V via CoreGraphics (`CGEvent`, key code 9, Command flag) → 400 ms wait → race-safe restore
- M4: `ClipboardRestoreService` — plain-text-only clipboard snapshot/restore; restores the prior clipboard if and only if the pasteboard change count still equals the value from Uttr's own write; never restores non-text content and never overwrites another app's newer clipboard
- M4: `Pasteboarding` and `KeyboardPosting` seams with `MockPasteboard`/`MockKeyboardPoster` test doubles — unit tests never touch the real clipboard or post real keyboard events
- M4: Paste failure UX — if Command-V posting fails, the transcript stays on the clipboard and the menu bar shows `Text copied — paste with Command-V.`
- M4: Programmatic permission requests — `Request Access` buttons in Onboarding and Permissions settings now trigger the system prompts for Microphone (`AVCaptureDevice.requestAccess`), Input Monitoring (`CGRequestListenEventAccess`), and Accessibility (`AXIsProcessTrustedWithOptions` with prompt), replacing manual-only System Settings navigation
- M4: Permission statuses re-check automatically when Uttr regains focus (returning from System Settings)
- M4: Clipboard behavior disclosure (non-text restoration limitation) added to Privacy settings
- M4: 12 new unit tests: clipboard snapshot/restore, change-count race, non-text clipboard limitation, paste-post failure, write-before-post ordering, and exact wait durations

- DictationState state machine with validated transitions and event-driven AppState
- ConfigurationStore with atomic JSON persistence, 0600/0700 file permissions, validation, and malformed-file recovery
- Settings window with five tabs: General, Transcription, Text Polish, Permissions, Privacy
- Plaintext API key disclosure in the Text Polish settings tab
- Onboarding flow shell with 5-step first-run experience and skip confirmation
- PermissionChecking protocol with injectable test doubles
- FileSystemProtocol for testable file operations
- RealPermissionService: microphone (AVCaptureDevice), input monitoring (CGEvent test), accessibility (AXIsProcessTrusted)
- EventTapHotkeyService: CGEventTap on dedicated serial queue, hold-to-talk with key-repeat suppression
- AppEnvironment wiring layer connecting hotkey events to AppState transitions
- Shortcut capture mode with Fn/Globe rejection, bare-key rejection, and reserved-shortcut guard
- Shortcut display and Change Shortcut UI in General settings
- PermissionAlertView info struct for permission-blocked state
- MockHotkeyService test double implementing HotkeyServiceProtocol
- 99 automated tests covering state transitions, config, permissions, hotkey flows, and shortcut capture
- Pre-M3 technical spike (`Spike/`): five isolated probes for microphone in-memory capture, active Quartz event tap, synthetic Command-V with race-safe clipboard restore, SpeechAnalyzer availability, and WhisperKit in-memory transcription
- `docs/SPIKE_REPORT.md`: consolidated spike findings, per-probe verification matrix, and outstanding owner validation steps
- `docs/DECISIONS.md`: ADR-001 through ADR-006 covering toolchain, SpeechAnalyzer availability, WhisperKit pinning, and event-tap permission behavior
- M3: `AudioRecording` protocol + `AVAudioEngineRecorder` — AVAudioEngine input-tap capture converted to mono 16 kHz Float32 entirely in memory; no audio ever written to disk
- M3: `AudioPolicy` — rejects dictations under 250 ms or with no meaningful signal; 120 s maximum duration
- M3: `WhisperKitEngine` + injectable `WhisperTranscribing` client seam; WhisperKit v1.0.0 behind `#if canImport` until the SPM dependency is wired (ADR-007)
- M3: `TranscriptionCoordinator` — engine selection (`automatic`/`systemSpeech`/`whisperKit`) with WhisperKit fallback, background model preparation, observable download/readiness state for Settings
- M3: `DictationController` — drives hotkey → record → validate → transcribe → paste-seam pipeline with max-duration timer and escape cancel; every failure path returns to idle
- M3: `PasteServicing` protocol + placeholder (real synthetic-paste implementation is M4 scope)
- M3: Transcription settings show live model preparation status and reconfigure the engine on selection change
- M3: 27 new unit tests (audio policy, engine mapping/trim/errors, coordinator selection/preparation/fallback, full pipeline happy path and every rejection path) with five new test doubles

### Changed

- WhisperKit pinned to v1.0.0 (commit `25c62997041c134b03ca82731ce2f6fd2cae1eb9`, MIT); `CapturedAudio` will carry `[Float]` 16 kHz mono to match the engine's `transcribe(audioArrays:)` entry point

### Notes

- SpeechAnalyzer/SpeechTranscriber remain **UNVERIFIED** for this project: absent from the macOS 15.0 SDK in Xcode 16.0 and unavailable at runtime on macOS 15.7.4. M3 uses WhisperKit; the engine stays runtime-configurable so M5 can add System Speech behind the existing `TranscriptionEngine` protocol (ADR-003, ADR-005)

## [0.0.1] - 2026-08-05

### Added

- Repository foundation: project skeleton, targets, and build configuration
- Menu-bar app shell with no Dock icon (LSUIElement)
- SwiftLint configuration
- CI workflow for pull requests and pushes to main
- Bootstrap, lint, and test scripts
- MIT license
- Project documentation stubs
