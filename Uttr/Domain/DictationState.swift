import Foundation

enum DictationState: Equatable {
    case idle
    case recording(startedAt: Date)
    case transcribing
    case polishing
    case pasting
    case awaitingHotkey
    case blocked(PermissionBlocker)
}

enum PermissionBlocker: Equatable {
    case microphone
    case inputMonitoring
    case accessibility
}
