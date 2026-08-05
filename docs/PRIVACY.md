# Privacy

## What stays on your Mac

- All microphone audio: captured, processed, and discarded locally
- Transcription processing: runs entirely on-device using Apple Speech or WhisperKit
- Configuration and settings: stored locally in `~/Library/Application Support/Uttr/`
- Operational logs: local only, contain no transcript content or audio

## What can leave your Mac (opt-in only)

When text polish is enabled by the user:

- **Final transcript text only** is sent to the selected provider (OpenAI or Anthropic)
- The request contains the transcript string and the configured model identifier
- No audio, device identifiers, clipboard contents, focused-app names, file paths, or metadata are included

## What is never collected

- Analytics or telemetry
- Device identifiers
- Usage statistics
- Crash reports
- Transcript history
- Audio recordings
