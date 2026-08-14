# Uttr

A menu-bar-only, hold-to-talk, local-first dictation app for macOS.

## Install from DMG

1. Build the DMG: `./Scripts/release-dmg.sh` → `build/Uttr-<version>.dmg` (SHA-256 checksum written alongside).
2. Open the DMG and drag **Uttr** to **Applications**.
3. First launch (pre-notarized builds): macOS Gatekeeper will warn that the app can't be verified. Right-click **Uttr.app** → **Open** → **Open**, or run `xattr -d com.apple.quarantine /Applications/Uttr.app`. This goes away once releases are Developer-ID signed and notarized (planned for v1.0).
4. On first launch, Uttr's setup walks you through the three required permissions (Microphone, Input Monitoring, Accessibility). Input Monitoring and Accessibility take effect only after you quit and reopen Uttr — the setup says so at the right steps.

## Updates

Uttr can check for updates from the menu bar ("Check for Updates…") or from Settings → General → Updates. Automatic checking is off by default. Until the app is Developer ID signed, updating may require you to re-grant Microphone, Input Monitoring, and Accessibility permissions afterward.

## Requirements

- Apple Silicon Mac (arm64)
- macOS 15.0 or later

## Features

- **Hold-to-talk dictation** — press Control+Option+Space to record, release to transcribe and paste
- **Local-first audio** — microphone audio never leaves your Mac
- **Automatic engine selection** — uses Apple SpeechAnalyzer on macOS 26+ with WhisperKit fallback on macOS 15–25
- **Optional text polish** — opt-in transcript cleanup via OpenAI or Anthropic (sends only final transcript text, never audio)
- **No Dock icon** — lives entirely in your menu bar

## Install

Download the latest signed and notarized DMG from [Releases](https://github.com/prithvibommu/uttr/releases). Drag `Uttr.app` to your Applications folder.

### First launch (pre-notarized dev builds)

If macOS shows a Gatekeeper warning for unsigned development builds, right-click the app and select Open, then confirm. This is not required for notarized release builds.

## Permissions

Uttr requires three macOS permissions:

1. **Microphone** — to capture your voice while you hold the dictation shortcut
2. **Input Monitoring** — to detect your global keyboard shortcut
3. **Accessibility** — to paste transcribed text into other applications

The first-run setup guides you through granting each permission.

## Default shortcut

**Control + Option + Space** — hold to record, release to transcribe and paste.

You can change this in Settings. The 🌐/Fn key is supported **on its own** as a hold-to-talk key: set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing” first, then capture it via Settings → Change Shortcut. Fn cannot be combined with other keys, and bare modifier-only shortcuts (e.g. just Control+Shift) remain unsupported.

## Offline behavior

Uttr works fully offline after required local model assets are downloaded. The optional cloud text polish feature requires an internet connection but is disabled by default.

## Optional text polish

When enabled in Settings, Uttr can send your final transcript text (never audio) to OpenAI or Anthropic for cleanup. This is opt-in and disabled by default. Only the transcript string is sent — no audio, device identifiers, clipboard contents, or metadata.

## API key storage

> **Important:** API keys for optional text polish are stored as plaintext in `~/Library/Application Support/Uttr/config.json`. This file is created with restricted permissions (0600). Use a provider spending limit and do not use a high-privilege key. See [SECURITY.md](docs/SECURITY.md) for details.

## Clipboard behavior

After pasting, Uttr restores your previous plain-text clipboard content if no other app has changed the clipboard. If the clipboard previously contained non-text data (images, files), restoration is not attempted. If paste fails, the transcribed text remains on your clipboard for manual pasting.

## Build from source

Prerequisites: Apple Silicon Mac, macOS 15+, and full Xcode **26.0 or newer**
(required for the macOS 26 System Speech implementation). Activate Xcode once:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

Clone and build:

```bash
git clone https://github.com/prithvi-bommu/uttr.git
cd uttr
./Scripts/bootstrap.sh
xcodebuild -project Uttr.xcodeproj -scheme Uttr -configuration Debug build
```

Run the tests:

```bash
./Scripts/test.sh
```

## Create a distributable DMG

```bash
./Scripts/release-dmg.sh
```

One command: builds Release (arm64), ad-hoc signs the app, packages
`build/Uttr-<version>.dmg` with a SHA-256 checksum, and opens the DMG window
for the drag-to-Applications install. The first build downloads Swift package
dependencies, so it needs internet access.

Note: until releases are Developer-ID signed and notarized, the DMG is ad-hoc
signed — recipients right-click → Open once (see "Install from DMG" above),
and Input Monitoring requires the drag-in add during setup.

## License

[MIT](LICENSE)
