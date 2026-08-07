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
    case aiRequestStarted
    case aiResponseReceived(String)
    case aiRequestFailed
    case pasteCompleted
    case pasteFailed
    case permissionBlocked(PermissionBlocker)
    case permissionResolved
    case beginHotkeyCapture
    case cancelHotkeyCapture
    case hotkeyCaptureDone
    case maxDurationReached

    /// Case name only — never includes associated values, so transcript
    /// contents can never reach a log line (privacy contract §11).
    var debugName: String {
        switch self {
        case .hotkeyDown: "hotkeyDown"
        case .hotkeyUp: "hotkeyUp"
        case .escapePressed: "escapePressed"
        case .recordingFailed: "recordingFailed"
        case .noUsableAudio: "noUsableAudio"
        case .transcriptionCompleted: "transcriptionCompleted"
        case .transcriptionFailed: "transcriptionFailed"
        case .polishCompleted: "polishCompleted"
        case .polishFailed: "polishFailed"
        case .aiRequestStarted: "aiRequestStarted"
        case .aiResponseReceived: "aiResponseReceived"
        case .aiRequestFailed: "aiRequestFailed"
        case .pasteCompleted: "pasteCompleted"
        case .pasteFailed: "pasteFailed"
        case .permissionBlocked(let blocker): "permissionBlocked(\(blocker))"
        case .permissionResolved: "permissionResolved"
        case .beginHotkeyCapture: "beginHotkeyCapture"
        case .cancelHotkeyCapture: "cancelHotkeyCapture"
        case .hotkeyCaptureDone: "hotkeyCaptureDone"
        case .maxDurationReached: "maxDurationReached"
        }
    }
}

@MainActor
@Observable
final class AppState {
    private(set) var dictationState: DictationState = .idle
    private(set) var lastTranscript: String?
    private(set) var pasteFailedText: String?

    /// Invoked after every accepted transition with the new state.
    /// Drives UI that lives outside the SwiftUI tree (recording indicator).
    @ObservationIgnored var onStateChange: ((DictationState) -> Void)?

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
        DebugFileLog.append("state", "Transition: \(String(describing: from)) -> \(String(describing: next)) (event: \(event.debugName))")
        onStateChange?(next)
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

        case (.transcribing, .noUsableAudio):
            // Audio validation happens after hotkey release (state already
            // .transcribing). A short/silent capture must return to idle,
            // otherwise the app is stuck and ignores all further hotkeys.
            return .idle

        case (.polishing, .polishCompleted(let text)):
            lastTranscript = text
            return .pasting

        case (.polishing, .polishFailed):
            return .pasting

        // AI-content mode: the transcript is a prompt, not the payload.
        case (.transcribing, .aiRequestStarted):
            return .prompting

        case (.prompting, .aiResponseReceived(let text)):
            lastTranscript = text
            return .pasting

        case (.prompting, .aiRequestFailed):
            // Nothing worth pasting on failure; return to idle so the
            // hotkeys keep working. The failure is logged and surfaced
            // through the indicator disappearing without a paste.
            return .idle

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
