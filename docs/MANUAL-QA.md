# Manual QA Checklist

## Test matrix

Test on at least two Apple Silicon Macs:

- [ ] Mac running macOS 26+ (System Speech available)
- [ ] Mac running macOS 15–25 (WhisperKit only)

## Pre-test setup

- [ ] Fresh install from DMG (or clean build)
- [ ] All permissions granted (Microphone, Input Monitoring, Accessibility)
- [ ] WhisperKit model downloaded (if applicable)

## Core dictation flow

- [ ] Control-Option-Space hold starts recording (menu bar icon changes)
- [ ] Release stops recording and begins transcription
- [ ] Transcribed text is pasted into the focused application
- [ ] Menu bar returns to Ready state

## Target applications

Test paste in each:

- [ ] TextEdit
- [ ] Safari (text field)
- [ ] Slack (or equivalent messaging app)
- [ ] VS Code (or equivalent editor)
- [ ] Browser form field

## Edge cases

- [ ] Very short recording (<250ms) does not paste
- [ ] 120-second max recording stops and transcribes
- [ ] Escape during recording cancels without paste
- [ ] Rapid press/release does not crash
- [ ] Double key-down does not start duplicate recording

## Clipboard behavior

- [ ] Previous text clipboard content is restored after paste
- [ ] If another app changes clipboard during paste, Uttr does not overwrite
- [ ] Non-text clipboard content is not restored (documented limitation)

## Settings

- [ ] Settings opens from menu bar
- [ ] Hotkey can be rebound
- [ ] Fn/Globe key is rejected in shortcut capture
- [ ] Engine selection works
- [ ] API key field is masked by default
- [ ] Plaintext storage disclosure is visible

## Permissions

- [ ] Missing permission shows guidance
- [ ] Open System Settings link works
- [ ] App does not crash with missing permissions

## Polish (if enabled)

- [ ] Polish with valid key works
- [ ] Polish with invalid key falls back to raw transcript
- [ ] Polish timeout falls back to raw transcript
- [ ] Test key button works

## First run

- [ ] Onboarding appears on first launch
- [ ] Skip confirmation works
- [ ] Permissions can be granted during onboarding

---

## Update safety smoke test (manual RC checklist)

These steps must be run manually before every release candidate because
GitHub-hosted runners cannot automate macOS TCC permission prompts.

### Prerequisites

- Two consecutive signed builds: an "old" build and the release candidate.
- A test Mac where Uttr has been installed before (existing TCC records).

### Scenario A — normal update, microphone previously granted

1. Install the **old** build from its DMG. Launch it and confirm microphone
   access is already granted (green badge in Settings → Permissions).
2. Quit Uttr. Install the **new RC build** DMG, replacing the old app.
3. Launch the new build.
4. **Expected**: microphone remains granted; no TCC prompt appears; no
   `tccutil reset` is logged. Confirm in Settings → Permissions.
5. **Expected**: `lastKnownBuildVersion` in `UserDefaults` is updated to the
   new `CFBundleVersion`.

### Scenario B — update with stale denied microphone record

1. Using the **old** build, revoke microphone access in
   System Settings → Privacy & Security → Microphone → Uttr (toggle off).
2. Confirm the status badge in Settings → Permissions shows "Not Granted".
3. Quit Uttr. Install the **new RC build** from its DMG.
4. Launch the new build.
5. **Expected**: a system microphone permission prompt appears.
6. Grant access. **Expected**: microphone status becomes "Granted" without
   requiring a restart.
7. Confirm normal dictation works end-to-end.

### Scenario C — transient tccutil failure (retry eligibility)

_This scenario requires simulating a tccutil failure, which is hard to do
cleanly in production. Document this test as a code-level regression check:
see `UpdatePermissionAdvisorTests.failedRepairDoesNotAdvanceMarker`._

- Confirm the unit test passes, which asserts: when `repairMicrophone()`
  returns `.resetFailed(...)`, the build marker is NOT advanced, so the next
  launch will attempt repair again.

### Scenario D — first install (no prior TCC record)

1. On a clean Mac (or after `tccutil reset Microphone com.uttr.app`), install
   the RC build.
2. Launch the app.
3. **Expected**: the standard onboarding / permission request flow appears.
   No automatic `tccutil reset` is triggered on first install.

### Scenario E — deliberate user denial (no prompt loop)

1. After a clean install, decline microphone access at the system prompt.
2. Quit and re-launch several times.
3. **Expected**: Uttr does NOT re-run `tccutil reset` on every launch for the
   same build. One repair attempt per build is the limit.
4. On the next build (version bump), one more prompt may appear; after that
   the loop stops again.

### Scenario F — manual "Repair & re-request" in Settings

1. With a stale denied microphone record (see Scenario B step 1–2), open
   Settings → Permissions.
2. Tap "Not working? Repair & re-request" under the Microphone row.
3. **Expected**: a system microphone prompt appears (or, if somehow granted,
   the badge turns green immediately with no prompt).

### Post-update Sparkle verification

- [ ] Sparkle appcast URL is reachable and the feed lists the new version.
- [ ] The signature in the appcast matches (use `Scripts/verify-sparkle-signature.swift`).
- [ ] Sparkle XPC services are present in the app bundle
  (`Uttr.app/Contents/XPCServices/org.sparkle-project.Installer*.xpc`).
- [ ] The `SUPublicEDKey` in `Info.plist` has not changed.

### Branch protection note

The new `Update Artifact Check` CI job verifies the Release build contains
Sparkle and the correct update configuration. It is safe to mark as required
in branch protection (it uses no signing secrets and passes on fork PRs).
The `Build & Test` job should also remain required. See the completion section
of `docs/DECISIONS.md` for context.
