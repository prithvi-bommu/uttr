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

### Probe status matrix (updated 2026-08-05, post-Xcode-16.0 install)

| # | Probe | Compile-verified | Runtime-verified | Notes |
|---|-------|------------------|------------------|-------|
| 1 | Mic auth + AVAudioEngine in-memory capture | **Yes** (swiftc, Xcode 16.0) | No — needs owner terminal (TCC prompt) | Requires terminal mic permission |
| 2 | CGEventTap down/up/repeat/disable-recovery | **Yes** | **Yes — owner-verified 2026-08-05** | Active tap required Input Monitoring + Accessibility for the terminal AND a full terminal relaunch before `CGEvent.tapCreate` succeeded — validates spec §9's "quit and reopen" guidance |
| 3 | Synthetic Cmd-V into TextEdit + clipboard restore | **Yes** | No — needs owner terminal (Accessibility) | |
| 4 | SpeechAnalyzer/SpeechTranscriber availability | **No — API absent from macOS 15.0 SDK** (Xcode 16.0) | Known-unavailable (macOS 15.7 < 26) | See ADR-003 and ADR-005 |
| 5 | WhisperKit in-memory transcription API | No (needs SPM resolve in project) | No | API surface verified by **source inspection** of pinned tag (ADR-004) |

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

---

## ADR-005: Xcode 16.0 installed — CLT issue resolved; two environment constraints recorded

- Date: 2026-08-05
- Status: Accepted
- Context: Full Xcode 16.0 (16A242d, macOS 15.0 SDK, Swift 6.0) was installed via Xcodes and activated with `xcode-select --switch`. This supersedes ADR-002's blocker. Baseline verification of the existing M0–M2 code and spike probes was performed.
- Evidence:
  - `xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug build` → **BUILD SUCCEEDED**.
  - Spike probes 1–3 compile cleanly with `swiftc -swift-version 6`.
  - Probe 4 fails at compile time: `cannot find 'SpeechTranscriber' in scope` — the macOS 15.0 SDK in Xcode 16.0 does not contain the macOS 26 Speech APIs.
  - `xcodebuild test` from the agent's sandboxed session fails with "Test runner never began executing tests after launching" — launching the GUI-hosted test runner requires an unsandboxed user session.
- Constraints recorded:
  1. **Agent-session sandbox:** Swift macro expansion (`@Observable`) requires `-disable-sandbox` (`OTHER_SWIFT_FLAGS='-disable-sandbox'`) when the agent invokes builds, because macOS forbids nested sandboxes. Owner-run builds in Terminal/Xcode and CI need no flag. Test execution (app-hosted runner) cannot run from the agent session at all; the owner runs `Scripts/test.sh` or `xcodebuild test` in Terminal.
  2. **SDK gap for M5:** Building the System Speech engine (M5) will require an Xcode with the macOS 26 SDK. Until then, all `SpeechAnalyzer` references must stay behind `#if canImport`-safe patterns or be excluded, and CI must pin an Xcode version accordingly. This does not affect M3/M4.
- Options considered: (1) upgrade to a newer Xcode now; (2) proceed with 16.0 for M3/M4 and revisit the SDK for M5. Option 2 chosen — M3 has no macOS 26 dependency.
- Decision: Proceed to M3 on Xcode 16.0. Owner executes runtime probes 1–3 and the test suite in Terminal.
- Consequences: The existing `SpeechAnalyzerEngine.swift` stub must remain API-free (no macOS 26 symbols) until M5's toolchain decision.
- Validation required: owner runs probes 1–3 per `Spike/` headers and reports results; owner runs full test suite to reconfirm the 99-test baseline on Xcode 16.0.

---

## ADR-006: Active event tap requires Input Monitoring **and** a process relaunch — confirms spec §9 restart guidance

- Date: 2026-08-05
- Status: Accepted
- Context: Probe 2 builds the real hold-to-talk tap the spec requires — an *active* (`.defaultTap`) `CGEventTap` that swallows Control-Option-Space so no space character reaches the focused app. Whether such a tap can be created depends on TCC state at the moment of creation.
- Evidence (owner-verified on the physical Mac, 2026-08-05):
  - First run: `CGEvent.tapCreate` returned nil → probe printed "Input Monitoring permission missing for this terminal" and exited 1.
  - After granting Input Monitoring (and Accessibility) to the terminal but **without** relaunching it: still failed.
  - After fully quitting and reopening the terminal: tap created successfully; Control-Option-Space produced the expected `hotkey DOWN` / `hotkey UP` transitions with auto-repeat suppressed and no space character inserted.
- Options considered: (1) attempt to detect and hot-reload TCC grants in-process; (2) accept the OS behavior and surface an explicit restart instruction in onboarding and the permissions UI.
- Decision: Option 2. macOS evaluates Input Monitoring eligibility at process start; there is no supported way to pick up the grant without relaunching. Uttr must therefore instruct the user to quit and reopen after granting Input Monitoring or Accessibility.
- Consequences:
  - Validates the existing requirement in spec §9 and onboarding steps 3–4 — that guidance is now grounded in observed behavior rather than documentation.
  - `PermissionService` must re-check status when the app regains focus, and the permission alert must offer a clear "quit and reopen" affordance rather than implying the grant takes effect immediately.
  - The same constraint applies to anyone running the spike probes: grant, then relaunch the terminal.
- Validation required: none for this finding — it is directly observed. Re-confirm inside the packaged app during M4/M7 fresh-install QA, since the app (unlike a terminal) is the process users will actually grant.

---

## ADR-007: WhisperKit SPM dependency wired — initial failure was duplicate pbxproj object IDs, not the Xcode version (SUPERSEDED diagnosis corrected)

- Date: 2026-08-05 (corrected same day)
- Status: Accepted
- Context: First attempt to add the WhisperKit package reference crashed `xcodebuild` with `-[XCRemoteSwiftPackageReference _setOwner:]: unrecognized selector`, initially attributed to Xcode 16.0 being unable to parse this 16.4-format project.
- Evidence (corrected): the identical crash reproduced on Xcode 16.4. Root cause: the hand-written patch reused object IDs `E0000090`/`E0000092`/`E0000093`, which already identified XCBuildConfiguration objects in this project — the parser resolved the `packageReferences` entry to a build configuration and crashed. Replacing them with unique 24-hex IDs fixed parsing on 16.4 immediately.
- Decision: WhisperKit v1.0.0 wired as `exactVersion` package reference with unique IDs; `Package.resolved` pinned (WhisperKit 1.0.0 + transitive swift-argument-parser 1.8.2). The `#if canImport(WhisperKit)` guard in `WhisperKitEngine.swift` is retained as a harmless belt-and-suspenders for package-less builds.
- Consequences: The agent-session workaround set ADR-005 documented gains one more flag: SPM manifest compilation also cannot nest in the agent sandbox, so agent-run resolves/builds pass `-IDEPackageSupportDisableManifestSandbox=YES`. Owner builds and CI are unaffected.
- Lesson recorded: never hand-pick short sequential pbxproj IDs; verify uniqueness or use full 24-hex random IDs.
- Validation required: end-to-end dictation with the tiny.en model (M3 Validator Packet).

---

## ADR-008: Owner amends spec §0 — bare Fn/Globe becomes a supported hotkey; shortcut rebinding defect root-caused

- Date: 2026-08-05
- Status: Accepted (owner-directed 2026-08-05, post-M4 validation)
- Context: Two owner-reported issues. (1) Changing the hotkey via Settings → Change Shortcut never works. (2) The owner wants to trigger dictation with the Fn/Globe key, which spec §0 locked out ("Fn/Globe: Unsupported. Reject it in shortcut capture… Do not attempt a special Fn hook.").
- Evidence:
  - Rebinding defect: `EventTapHotkeyService.installEventTap()` runs on the service's serial dispatch queue and calls `CFRunLoopRun()`, which never returns. Every later `queue.async` block — `beginCapture()`, `updateHotkey()`, `cancelCapture()`, `stop()` — waits behind it forever. The capture UI appears (AppState transitions) but the tap never enters capture mode. M2's "rebinding works" acceptance was validated only against `MockHotkeyService`; the real tap path was never physically exercised for rebinding. Two latent defects found in the same code: rejection paths never reset `isCapturing` (a rejected capture would swallow the entire keyboard once reachable), and capture sampled modifier flags at key-up, falsely rejecting when the user releases modifiers before the main key.
  - Fn feasibility: the Fn/Globe key surfaces to a CGEventTap as `flagsChanged` events with keyCode 63 and `.maskSecondaryFn` set on press / cleared on release — a reliable hold/release boundary. Commercial dictation apps (e.g. Wispr Flow) ship exactly this, requiring the user to set System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing" so the system emoji/input-switch action does not also fire. Uttr cannot change that system setting programmatically.
- Options considered:
  1. Keep the spec lock, fix only rebinding.
  2. Amend spec §0: support **bare Fn/Globe** as an alternative hold-to-talk hotkey (press-and-hold Fn alone), while continuing to reject Fn as a *modifier in combination* with other keys (Fn+K etc.), which macOS handles inconsistently.
- Decision: Option 2, directed by the owner. Spec §0's "Fn/Globe: Unsupported" row and §6's "non-Fn normal key" validation rule are amended: `hotkey.keyCode == 63` with an empty modifier set is now valid. Modifier-only shortcuts (bare Ctrl/Shift chords) remain forbidden — the false-trigger rationale stands; bare Fn is exempt because Fn participates in no typing chords. Rebinding is fixed by extracting the tap's decision logic into a pure, lock-protected `HotkeyEventProcessor` mutated synchronously (no dispatch onto the blocked run-loop queue) and unit-tested directly.
- Consequences:
  - Users can capture bare Fn in Change Shortcut; Settings/README must instruct setting "Press 🌐 key to: Do Nothing" and disclose that Fn+key combinations remain unsupported.
  - `flagsChanged` Fn events are passed through (not swallowed): with the Globe action set to "Do Nothing" there is no side effect; swallowing modifier-state events could corrupt other apps' modifier tracking.
  - The M2-era claim that rebinding worked is retracted; regression tests now cover the processor directly.
- Validation required: owner physically validates (a) rebinding to a modifier+key combo, (b) capturing bare Fn, (c) Fn hold-to-talk end-to-end after setting Globe to "Do Nothing", (d) Escape cancel and rejection paths leave the keyboard functional.

---

## ADR-009: macOS 15 does not auto-register ad-hoc-signed apps in the Input Monitoring pane — assisted manual add until M7

- Date: 2026-08-05
- Status: Accepted
- Context: The DMG onboarding flow requests all three permissions programmatically. Owner validation on macOS 15.7.4 with the ad-hoc-signed DMG install showed asymmetric behavior on the same build and flow.
- Evidence (owner-verified):
  - Microphone: `AVCaptureDevice.requestAccess` → system prompt appears, works.
  - Accessibility: `AXIsProcessTrustedWithOptions(prompt)` → Uttr row auto-appears in the pane; user toggles it on.
  - Input Monitoring: `CGRequestListenEventAccess()` (including after `tccutil reset ListenEvent com.uttr.app`) → no prompt, no row; the pane opens empty of Uttr and the user must add the app manually.
- Analysis: TCC on macOS 15 declines to create Input Monitoring (ListenEvent) client records for ad-hoc-signed binaries via the request API, while the Accessibility path still registers them. Manual adds (drag-and-drop or "+") work and persist per binary fingerprint.
- Options considered: (1) accept "+"-and-browse; (2) assisted manual add — open the pane AND reveal Uttr.app in Finder so the user drags the icon into the list, with instructions in the onboarding note; (3) Developer ID signing now.
- Decision: Option 2 for all pre-M7 builds (`revealAppForManualAdd()`, wired into onboarding and Permissions settings). Option 3 (Developer ID + notarization, M7) is the root-cause fix that makes registration automatic.
- Consequences: The Input Monitoring onboarding step documents the drag-in path; the repair flow (ADR-context in `repairInputMonitoring()`) remains for genuinely stale-record cases but cannot force registration for ad-hoc builds.
- Validation required: after M7 signing, re-verify that `CGRequestListenEventAccess()` prompts and auto-registers, then simplify the step.

## ADR-010: Self-signed code-signing cert for local builds — Developer ID (M7) migration is one env var away

- Date: 2026-08-06
- Status: Accepted
- Context: TCC keys every permission grant (Microphone, Input Monitoring, Accessibility) — and `SMAppService` login-item registration — to the app's code-signing designated requirement. Ad-hoc signing (`codesign --sign -`) degrades that requirement to the binary's cdhash, which changes on every rebuild, so macOS treats each new DMG as a different app and wipes all grants (the daily "re-add permissions" loop; see ADR-009 for the related Input Monitoring registration failure).
- Decision: Interim fix now, real fix at M7:
  1. **Now**: a free self-signed certificate, **"Uttr Dev Signing"** (10-year validity, codeSigning EKU, trusted for code signing in the login keychain). Signing with it anchors the designated requirement to the certificate leaf (`certificate leaf = H"68e2a535…"`), which is stable across rebuilds — grants persist on the developer machine. Created via `openssl req` + `openssl pkcs12 -export -legacy` (OpenSSL 3's default PKCS12 format is not importable by macOS `security import`) + `security add-trusted-cert -p codeSign`.
  2. **M7**: an Apple **Developer ID Application** certificate + notarization (`Scripts/notarize.sh`, already written) for external distribution and automatic Input Monitoring registration.
- Migration path (deliberately zero-effort): `Scripts/release-dmg.sh` resolves the signing identity in priority order — `$UTTR_SIGN_IDENTITY` override → any "Developer ID Application" identity in the keychain → "Uttr Dev Signing" → ad-hoc fallback. **Installing the Developer ID cert is the entire migration**; the next `release-dmg.sh` run picks it up automatically. No script edits, no flag changes.
- Consequences:
  - One-time cost per identity switch (ad-hoc → self-signed now; self-signed → Developer ID at M7): macOS sees a "different app" once, so Mic/Input Monitoring/Accessibility must be re-granted one final time and login-item registration re-applied. After that, grants survive rebuilds.
  - The self-signed cert helps only on Macs that trust it — external recipients still need right-click → Open until M7 notarization.
  - After M7, re-verify ADR-009 (`CGRequestListenEventAccess()` should then prompt and auto-register) and simplify that onboarding step.

---

## ADR-011: Sparkle auto-updates ship with automatic checks disabled until Developer ID signing (M7)

- Date: 2026-08-14
- Status: Accepted
- Context: Uttr now integrates the Sparkle framework (v2.9.5) for over-the-air updates. CI builds produce a signed DMG, generate an EdDSA-signed appcast, and publish it to GitHub Pages. However, CI builds are ad-hoc signed (`codesign --sign -`), and per ADR-010, ad-hoc signing degrades the designated requirement to the binary's cdhash, which changes on every build.
- Evidence:
  - Per ADR-010, macOS keys every TCC grant (Microphone, Input Monitoring, Accessibility) and `SMAppService` login-item registration to the app's code-signing designated requirement.
  - Ad-hoc signing produces a cdhash-based designated requirement that changes on every build.
  - Therefore, every Sparkle auto-update is seen by macOS as a different application: all three permission grants are wiped, and the launch-at-login registration is dropped.
  - Per ADR-009, re-granting Input Monitoring on ad-hoc builds requires a manual drag-into-the-pane, which users will not discover on their own.
  - An unattended auto-update on an ad-hoc-signed build leaves users with a broken app that appears installed but silently does nothing.
- Options considered:
  1. Ship with automatic checks enabled (`SUEnableAutomaticChecks = true`) and accept the permission-loss UX — users will figure it out.
  2. Ship with automatic checks disabled by default (`SUEnableAutomaticChecks = false`, `SUAllowsAutomaticUpdates = false`) so updating is always a deliberate, informed user action with a visible warning about the consequences.
  3. Delay Sparkle integration entirely until Developer ID signing (M7).
- Decision: Option 2. The following defaults are set in `Info.plist`:
  - `SUEnableAutomaticChecks = false` — first launch defaults to "do not check automatically."
  - `SUAllowsAutomaticUpdates = false` — never install silently.
  - `SUScheduledCheckInterval = 86400` — once checks are enabled, poll every 24 hours.
  The user can enable automatic checking via Settings → General → Updates, where a visible warning explains the permission-loss consequence. The "Check for Updates…" menu bar item provides on-demand checking.
- Consequences:
  - Users who enable automatic checks will be offered updates but must confirm installation. They are warned that permissions may need to be re-granted.
  - Once a Developer ID Application certificate is in use (M7), the designated requirement anchors to the stable certificate leaf, grants survive updates, and this caveat evaporates. At that point: flip `SUEnableAutomaticChecks` to `true`, optionally set `SUAllowsAutomaticUpdates` to `true`, and remove the Settings warning.
  - The EdDSA signing key (`SPARKLE_PRIVATE_KEY` repository secret) is critical infrastructure: if lost, every already-installed copy of Uttr becomes permanently un-updatable because they only trust the public key baked into their bundle.
- Validation required: After M7, the maintainer must (1) verify that TCC permissions survive a Sparkle update with Developer ID signing, (2) flip `SUEnableAutomaticChecks` to `true` in `Info.plist`, (3) remove the `// TODO(M7)` warning from `GeneralSettingsView.swift`, and (4) update the README and RELEASE.md notes.
