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
- 73 automated tests covering state transitions, config encoding, validation rules, permissions, and sanitization

## [0.0.1] - 2026-08-05

### Added

- Repository foundation: project skeleton, targets, and build configuration
- Menu-bar app shell with no Dock icon (LSUIElement)
- SwiftLint configuration
- CI workflow for pull requests and pushes to main
- Bootstrap, lint, and test scripts
- MIT license
- Project documentation stubs
