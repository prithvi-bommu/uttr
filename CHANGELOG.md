# Changelog

All notable changes to Uttr will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
