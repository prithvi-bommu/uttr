# Decision Records — Uttr

Format defined in `UTTR_MASTER_AGENT_OPERATING_PROMPT.md`.

---

## ADR-001: Spike environment and verification status

- Date: 2026-08-05
- Status: Accepted
- Context: The pre-M3 technical spike (`spike/physical-macos-integration`) was executed on the owner's physical Apple Silicon Mac running macOS 15.7.4 (24G517). Full Xcode is **not installed**; only Command Line Tools (Swift 6.2.4, SDK 26.2) are present, and that toolchain is broken (ADR-002).
- Evidence: `sw_vers` → macOS 15.7.4; `xcodebuild -version` → "requires Xcode"; no `Xcode.app` under `/Applications`.
- Options considered: (1) proceed with compile+runtime verification after Xcode install; (2) write probes now, verify later.
- Decision: Probes 1–5 are **written and source-verified** but **not yet compiled or run** on this machine. Verification statuses below are explicit per probe. Nothing in this spike is claimed as physically validated until the owner (or agent, post-Xcode) runs the probes.
- Consequences: M3 implementation can be authored against verified API surfaces (probe 5 used source inspection of the pinned dependency), but the milestone cannot be declared complete until `xcodebuild build`/`test` pass and the Validator Packet is executed on this Mac.
- Validation required: install full Xcode, run `sudo xcode-select -s /Applications/Xcode.app`, then compile and run each probe per the header comments in `Spike/`.

### Probe status matrix

| # | Probe | Compile-verified | Runtime-verified | Notes |
|---|-------|------------------|------------------|-------|
| 1 | Mic auth + AVAudioEngine in-memory capture | No (ADR-002) | No | Requires terminal mic permission |
| 2 | CGEventTap down/up/repeat/disable-recovery | No (ADR-002) | No (M2 logic proven via unit tests only) | Requires Input Monitoring |
| 3 | Synthetic Cmd-V into TextEdit + clipboard restore | No (ADR-002) | No | Requires Accessibility |
| 4 | SpeechAnalyzer/SpeechTranscriber availability | No (ADR-002) | **Known-unavailable at runtime** (macOS 15.7 < 26) | See ADR-003 |
| 5 | WhisperKit in-memory transcription API | No (toolchain) | No | API surface verified by **source inspection** of pinned tag (ADR-004) |

---

## ADR-002: Command Line Tools toolchain is broken; full Xcode is required

- Date: 2026-08-05
- Status: Accepted
- Context: All spike compilation attempts fail before reaching project code.
- Evidence: `swiftc` on any file importing Foundation/AVFoundation/CoreGraphics fails with (a) `redefinition of module 'SwiftBridging'` (duplicate modulemap in `/Library/Developer/CommandLineTools/usr/include/swift/`) and (b) `failed to build module 'CoreFoundation'; this SDK is not supported by the compiler` — SDK interfaces built with swiftlang-6.2.3.3.2 while the installed compiler is swiftlang-6.2.4.1.4. `swift package resolve` also fails (PackageDescription link error), blocking SPM entirely.
- Options considered: (1) reinstall/downgrade CLT to match the SDK; (2) install full Xcode, which bundles a self-consistent toolchain+SDK and provides `xcodebuild` required by the workflow rules anyway.
- Decision: Install full Xcode (App Store). Do not patch the CLT — Xcode is mandatory for the milestone gates (`xcodebuild build`/`test`) regardless.
- Consequences: All compile/run verification is deferred until Xcode is installed. No code merged in the meantime may be described as tested.
- Validation required: `xcodebuild -version` succeeds after `xcode-select -s /Applications/Xcode.app`; probes compile.

---

## ADR-003: SpeechAnalyzer/SpeechTranscriber unavailable at runtime on this Mac — WhisperKit carries M3; System Speech stays a configurable engine for M5

- Date: 2026-08-05
- Status: Accepted (owner-confirmed 2026-08-05)
- Context: The spec prefers Apple `SpeechAnalyzer`/`SpeechTranscriber` on macOS 26+, with WhisperKit as the macOS 15–25 fallback. The owner's validation Mac runs macOS 15.7.4, so the System Speech path **cannot be runtime-verified on this machine**. Compile-time availability is plausible (CLT ships SDK 26.2, and the full Xcode release will include the macOS 26 SDK) but is unverified until Xcode is installed.
- Evidence: `sw_vers` → 15.7.4; `#available(macOS 26.0, *)` is false at runtime here. Probe 4 (`Spike/probe4_speechanalyzer.swift`) encodes both the compile-time and runtime checks and will report asset/locale status when run on a macOS 26 machine.
- Options considered: (1) block M3 on obtaining a macOS 26 device; (2) proceed with WhisperKit for M3 (spec already mandates this fallback) and keep System Speech behind the existing `TranscriptionEngine` protocol + `automatic|systemSpeech|whisperKit` setting for M5.
- Decision: Option 2. M3 rides entirely on WhisperKit. The engine remains **runtime-configurable** via `Settings.transcriptionEngine`; `automatic` resolves to WhisperKit on macOS < 26 and will prefer System Speech on macOS 26+ once M5 lands. All macOS 26 API use stays behind `if #available(macOS 26.0, *)` so no such API is touched on older systems.
- Consequences: **UNVERIFIED marker for the owner:** SpeechAnalyzer/SpeechTranscriber availability, asset download flow, and transcription quality have NOT been verified in this project. When a macOS 26+ Mac is available, run probe 4 there; if the APIs hold, M5 plugs the engine in behind the existing protocol without rearchitecting.
- Validation required: run `Spike/probe4_speechanalyzer.swift` on a macOS 26+ Apple Silicon Mac; record supported/installed locales and the asset-installation flow before starting M5.

---

## ADR-004: Pin WhisperKit v1.0.0; in-memory transcription API confirmed by source inspection

- Date: 2026-08-05
- Status: Accepted
- Context: The spec requires WhisperKit via SPM, pinned to a published stable release, transcribing in-memory audio with no file URL (`CapturedAudio` has no file URL property).
- Evidence:
  - Latest stable tag: `v1.0.0`, commit `25c62997041c134b03ca82731ce2f6fd2cae1eb9` (`git ls-remote --tags https://github.com/argmaxinc/WhisperKit.git`).
  - License: MIT (compatible with this repository's MIT license).
  - Source inspection of the tag confirms `open func transcribe(audioArrays: [[Float]], decodeOptions:, callback:) async -> [[TranscriptionResult]?]` in `Sources/WhisperKit/Core/WhisperKit.swift` — pure in-memory Float32 input, 16 kHz mono expected.
  - `WhisperKitConfig(model:...)` supports named models incl. `openai_whisper-{tiny,base,small,medium}.en`; `small.en` appears as a default recommendation in `Models.swift`. Models download to WhisperKit's application-support location, not the app bundle.
- Options considered: (1) pin v1.0.0; (2) pin the older v0.18.0 line for maturity. v1.0.0 is a published stable release and matches the "current stable at implementation time" rule.
- Decision: Pin `WhisperKit` at `exact: "1.0.0"`. Record the resolved revision in the first dependency commit's `Package.resolved` (blocked until Xcode is installed — ADR-002).
- Consequences: `AudioRecorder` should produce Float32 16 kHz mono samples (`[Float]`) as the canonical `CapturedAudio` payload, avoiding an extra Int16 conversion step, since the engine consumes `[Float]` directly.
- Validation required: `swift package resolve` post-Xcode must produce a `Package.resolved` with revision `25c62997041c134b03ca82731ce2f6fd2cae1eb9`; probe 5 must load `tiny.en` and transcribe an in-memory buffer end-to-end on this Mac.
