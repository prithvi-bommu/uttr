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
