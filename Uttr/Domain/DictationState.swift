import Foundation

enum DictationState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case polishing
    case pasting
    case awaitingHotkey
    case blocked(PermissionBlocker)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording…"
        case .transcribing: "Transcribing…"
        case .polishing: "Polishing…"
        case .pasting: "Pasting…"
        case .awaitingHotkey: "Press your shortcut…"
        case .blocked(let blocker): blocker.statusText
        }
    }

    var menuBarIcon: String {
        switch self {
        case .idle: "mic.circle"
        case .recording: "mic.circle.fill"
        case .transcribing, .polishing, .pasting: "ellipsis.circle"
        case .awaitingHotkey: "keyboard"
        case .blocked: "exclamationmark.triangle"
        }
    }
}

enum PermissionBlocker: Equatable, Sendable {
    case microphone
    case inputMonitoring
    case accessibility

    var statusText: String {
        switch self {
        case .microphone: "Microphone permission required"
        case .inputMonitoring: "Input Monitoring permission required"
        case .accessibility: "Accessibility permission required"
        }
    }
}
