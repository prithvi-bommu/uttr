import Foundation
import OSLog

enum DictationEvent: Sendable {
    case hotkeyDown
    case hotkeyUp
    case escapePressed
    case recordingFailed
    case noUsableAudio
    case transcriptionCompleted(String)
    case transcriptionFailed
    case polishCompleted(String)
    case polishFailed
    case pasteCompleted
    case pasteFailed
    case permissionBlocked(PermissionBlocker)
    case permissionResolved
    case beginHotkeyCapture
    case cancelHotkeyCapture
    case hotkeyCaptureDone
    case maxDurationReached
}

@MainActor
@Observable
final class AppState {
    private(set) var dictationState: DictationState = .idle
    private(set) var lastTranscript: String?
    private(set) var pasteFailedText: String?

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.uttr.app", category: "state")

    var canChangeSettings: Bool {
        dictationState.isIdle
    }

    @discardableResult
    func handle(_ event: DictationEvent) -> Bool {
        let from = dictationState
        guard let next = nextState(from: from, event: event) else {
            logger.debug("Ignored event in state \(String(describing: from))")
            return false
        }
        dictationState = next
        logger.info("Transition: \(String(describing: from)) -> \(String(describing: next))")
        return true
    }

    private func nextState(from state: DictationState, event: DictationEvent) -> DictationState? {
        switch (state, event) {
        case (.idle, .hotkeyDown):
            return .recording(startedAt: Date())

        case (.idle, .beginHotkeyCapture):
            return .awaitingHotkey

        case (.idle, .permissionBlocked(let blocker)):
            return .blocked(blocker)

        case (.recording, .hotkeyUp):
            return .transcribing

        case (.recording, .escapePressed):
            lastTranscript = nil
            return .idle

        case (.recording, .recordingFailed):
            return .idle

        case (.recording, .noUsableAudio):
            return .idle

        case (.recording, .maxDurationReached):
            return .transcribing

        case (.recording, .hotkeyDown):
            return nil

        case (.transcribing, .transcriptionCompleted(let text)):
            lastTranscript = text
            return .polishing

        case (.transcribing, .transcriptionFailed):
            return .idle

        case (.polishing, .polishCompleted(let text)):
            lastTranscript = text
            return .pasting

        case (.polishing, .polishFailed):
            return .pasting

        case (.pasting, .pasteCompleted):
            pasteFailedText = nil
            return .idle

        case (.pasting, .pasteFailed):
            pasteFailedText = lastTranscript
            return .idle

        case (.awaitingHotkey, .hotkeyCaptureDone):
            return .idle

        case (.awaitingHotkey, .cancelHotkeyCapture):
            return .idle

        case (.blocked, .permissionResolved):
            return .idle

        default:
            return nil
        }
    }
}
