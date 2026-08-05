# Architecture

## Component diagram

```
┌─────────────────────────────────────────────┐
│                  UttrApp                     │
│  ┌──────────┐  ┌───────────┐  ┌──────────┐ │
│  │ MenuBar  │  │ Settings  │  │Onboarding│ │
│  │  View    │  │  Window   │  │   Flow   │ │
│  └────┬─────┘  └─────┬─────┘  └────┬─────┘ │
│       └───────┬───────┘             │       │
│               ▼                     │       │
│         ┌──────────┐                │       │
│         │ AppState │◄───────────────┘       │
│         └────┬─────┘                        │
│              │                              │
│  ┌───────────┴──────────────────────┐       │
│  ▼           ▼          ▼           ▼       │
│ Hotkey    Audio     Transcription  Paste    │
│ Service   Recorder  Coordinator   Service   │
│  │                   │      │       │       │
│  │          ┌────────┴──┐   │       │       │
│  │          ▼           ▼   ▼       │       │
│  │     System      Whisper  Text    │       │
│  │     Speech      Kit     Polisher │       │
│  │     Engine      Engine   │       │       │
│  │                         ┌┴──┐    │       │
│  │                    OpenAI  Anthropic     │
│  │                                  │       │
│  └──────────────────────────────────┘       │
│                                             │
│  ┌─────────────────────────────────────┐    │
│  │ ConfigurationStore │ PermissionSvc  │    │
│  │ LogService        │ LoginItemSvc   │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Dependency direction

All dependencies flow inward. Features depend on Domain. Services implement Domain protocols. No service depends on a feature or on another service except through Domain interfaces.

## Key design decisions

- **State machine**: `DictationState` is the single source of truth for the entire dictation flow
- **Protocol-driven services**: All platform adapters are behind protocols for testability
- **No App Sandbox**: Required for global event tap and cross-app paste
- **LSUIElement**: No Dock icon; menu-bar-only presence
