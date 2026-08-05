# Pre-M3 Technical Spike Report

**Branch:** `spike/physical-macos-integration`
**Date:** 2026-08-05
**Purpose:** Establish, by direct observation rather than assumption, the platform and dependency facts M3 depends on — before any production code is written.
**Mandate:** `UTTR_MASTER_AGENT_OPERATING_PROMPT.md` § "Technical discovery rule".

This spike produces **facts and decision records only**. No production architecture was added. Nothing here is intended to merge into the app target.

---

## 1. Environment

| Item | Value | How established |
|---|---|---|
| Machine | Apple Silicon Mac (owner's physical validation Mac) | — |
| macOS | 15.7.4 (24G517) | `sw_vers` |
| Xcode | 16.0 (16A242d) | `xcodebuild -version` |
| SDK | macOS 15.0 | `xcrun --show-sdk-version` after switch |
| Swift | 6.0 (swiftlang-6.0.0.9.10) | `swiftc --version` |
| Developer dir | `/Applications/Xcode-16.0.0.app/Contents/Developer` | `xcode-select -p` |

Xcode was installed mid-spike (via the Xcodes manager). Before that, only Command Line Tools were present and were internally inconsistent — see ADR-002.

---

## 2. What was built

Five isolated probes under `Spike/`, each a single self-contained Swift file with its build/run instructions in the file header. They deliberately share no code with the app target.

| File | Question it answers |
|---|---|
| `Spike/probe1_audio_capture.swift` | Can we get mic authorization and capture PCM through `AVAudioEngine` entirely in memory, and convert to the format the transcription engine wants? |
| `Spike/probe2_event_tap.swift` | Does an *active* Quartz event tap reliably see Control-Option-Space key-down/key-up, suppress auto-repeat, swallow the trigger so no space is typed, and recover when macOS disables it? |
| `Spike/probe3_paste.swift` | After Accessibility is granted, can we post synthetic Command-V into another app and restore the prior clipboard race-safely? |
| `Spike/probe4_speechanalyzer.swift` | Are `SpeechAnalyzer`/`SpeechTranscriber` available at compile time and at run time here, and what does the language-asset flow look like? |
| `Spike/probe5_whisperkit.swift` | What is the exact WhisperKit API for transcribing in-memory audio with no file on disk? |

Each probe encodes the spec's actual required behavior, not a simplified version. Probe 2 uses `.defaultTap` (an active tap) because the spec requires swallowing the hotkey. Probe 3 implements the full spec §9 sequence: snapshot text-only clipboard → write → 50 ms → post Cmd-V → 400 ms → restore *only if* `changeCount` is unchanged.

---

## 3. Results

### 3.1 Verification matrix

| # | Probe | Compiles | Runs correctly | Verified by |
|---|---|---|---|---|
| 1 | Mic + in-memory capture | ✅ | ⬜ not yet run | — |
| 2 | Event tap / hold-to-talk | ✅ | ✅ **owner-verified** | Owner, Terminal, 2026-08-05 |
| 3 | Synthetic Cmd-V + clipboard restore | ✅ | ⬜ not yet run | — |
| 4 | SpeechAnalyzer availability | ❌ **API absent from SDK** | ❌ unavailable at runtime | Agent (compile) + OS version |
| 5 | WhisperKit in-memory API | ⬜ needs SPM in-project | ⬜ | API surface verified by source inspection |

Legend: ✅ observed working · ❌ observed failing · ⬜ not yet exercised.

**Nothing in this table is inferred.** A blank cell means the check has not been performed, not that it is assumed to pass.

### 3.2 Existing code baseline

`xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug build` → **BUILD SUCCEEDED**. This is the first time the merged M0–M2 code has been compiled on this machine.

The test suite (99 tests) has **not** yet been re-run here. Test execution requires a normal user session (see §4.1), so it is an owner step.

### 3.3 Probe 2 — the substantive behavioral finding

First run failed outright:

```
CGEvent.tapCreate FAILED — Input Monitoring permission missing for this terminal
```

It succeeded only after the terminal was granted **Input Monitoring** *and* **fully quit and relaunched**. Toggling the permission on a running process was not sufficient.

This is not merely a spike inconvenience — it independently confirms the product requirement in spec §9 that Uttr must tell users to quit and reopen the app after granting Input Monitoring/Accessibility, and that the onboarding flow (steps 3 and 4) must carry that restart note. The permission-gating UX has a real observed basis now rather than a documentation-derived one.

### 3.4 Probe 4 — SpeechAnalyzer is not reachable here

Two independent reasons, both observed:

- **Compile time:** `cannot find 'SpeechTranscriber' in scope`. Xcode 16.0 ships the macOS 15.0 SDK; the macOS 26 Speech APIs are not in it.
- **Run time:** the machine is macOS 15.7.4, so `#available(macOS 26.0, *)` is false regardless of SDK.

Consequences, recorded in ADR-003 and ADR-005:

- M3 rides entirely on WhisperKit. The spec already designates this as the macOS 15–25 path, so this is conformance, not a deviation.
- The engine choice stays **runtime-configurable** through `Settings.transcriptionEngine` (`automatic` / `systemSpeech` / `whisperKit`) behind the `TranscriptionEngine` protocol. When a macOS 26 machine and a macOS 26 SDK are both available, M5 plugs the System Speech engine in behind that protocol with no rearchitecting.
- **This item is explicitly UNVERIFIED and carried forward.** Nobody should treat SpeechAnalyzer support as proven for this project until probe 4 runs green on macOS 26+.

### 3.5 Probe 5 — WhisperKit pinned and API confirmed

| Item | Value |
|---|---|
| Version | `v1.0.0` |
| Commit | `25c62997041c134b03ca82731ce2f6fd2cae1eb9` |
| License | MIT — compatible with this repo's MIT license |
| In-memory API | `open func transcribe(audioArrays: [[Float]], decodeOptions:, callback:) async -> [[TranscriptionResult]?]` |
| Config | `WhisperKitConfig(model:)`, models `openai_whisper-{tiny,base,small,medium}.en` |
| Model location | WhisperKit's application-support directory — never the app bundle |

Established by cloning the tag and reading `Sources/WhisperKit/Core/WhisperKit.swift`, not from documentation or memory. The `audioArrays: [[Float]]` entry point takes samples with no file URL anywhere in the call, which satisfies the spec's requirement that `CapturedAudio` have no file-URL property and that no audio touch disk in the normal path.

**Design consequence for M3:** `CapturedAudio` should carry `[Float]` at 16 kHz mono. The engine consumes `[Float]` directly, so an Int16 conversion step the spec permits is unnecessary work.

---

## 4. Constraints discovered (carry into M3 and CI)

### 4.1 Agent-session sandbox

The agent's shell runs sandboxed, which produces two effects that are **environmental, not defects in the project**:

- Swift macro expansion (`@Observable`) fails with `swift-plugin-server produced malformed response`, because macOS forbids nested sandboxes. Workaround for agent-run builds only: `OTHER_SWIFT_FLAGS='-disable-sandbox'`. Owner-run builds in Terminal/Xcode and GitHub Actions need no such flag.
- App-hosted test runners cannot launch at all (`Test runner never began executing tests after launching`). Running the test suite is therefore an owner step, permanently.

### 4.2 macOS 26 SDK gap

M5 requires an Xcode carrying the macOS 26 SDK. Until then `Uttr/Services/SpeechAnalyzerEngine.swift` must stay free of macOS 26 symbols so the project keeps building on Xcode 16.0, and CI must pin a compatible Xcode. M3 and M4 are unaffected.

---

## 5. Decision records

Full entries in `docs/DECISIONS.md`:

| ADR | Subject | Status |
|---|---|---|
| ADR-001 | Spike environment, scope, and per-probe verification matrix | Accepted |
| ADR-002 | Command Line Tools toolchain broken; full Xcode required | Accepted (resolved by ADR-005) |
| ADR-003 | SpeechAnalyzer unavailable → WhisperKit carries M3; System Speech stays configurable for M5 | Accepted (owner-confirmed) |
| ADR-004 | Pin WhisperKit v1.0.0; in-memory API confirmed by source inspection | Accepted |
| ADR-005 | Xcode 16.0 installed; agent-sandbox and SDK-gap constraints recorded | Accepted |
| ADR-006 | Event tap requires permission **and** process relaunch (owner-verified) | Accepted |

---

## 6. Outstanding owner actions

1. Run `xcodebuild ... test` in Terminal to reconfirm the 99-test baseline on Xcode 16.0.
2. Run probe 1 (`/tmp/p1 3`, speak ~3 s) and confirm nonzero frames, nonzero peak, and converter availability.
3. Run probe 3 with TextEdit focused and confirm the paste lands and the clipboard is restored.
4. Decide the disposition of this branch: merge the documentation only, or merge docs and delete `Spike/` per the operating prompt's "do not blindly merge exploratory code" rule.

Until items 1–3 are done, the corresponding matrix rows in §3.1 stay blank. They will not be marked verified on anyone's assumption.

---

## 7. Verdict

M3 is unblocked. The one spec-preferred capability that is genuinely unavailable (SpeechAnalyzer) is unavailable for reasons that are documented, twice-confirmed, and already accommodated by a configurable engine abstraction the spec itself requires — so it defers cleanly to M5 rather than forcing a workaround.
