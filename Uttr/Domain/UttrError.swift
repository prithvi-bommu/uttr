import Foundation

enum UttrError: LocalizedError {
    case microphonePermissionDenied
    case inputMonitoringPermissionDenied
    case accessibilityPermissionDenied
    case audioCaptureFailed(underlying: Error)
    case transcriptionFailed(underlying: Error)
    case polishFailed(underlying: Error)
    case pasteFailed
    case configurationCorrupted
    case noUsableAudio
    case recordingTooShort
    case engineNotReady

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission is required for dictation."
        case .inputMonitoringPermissionDenied:
            "Input Monitoring permission is required to detect your shortcut."
        case .accessibilityPermissionDenied:
            "Accessibility permission is required to paste text."
        case .audioCaptureFailed:
            "Audio capture failed."
        case .transcriptionFailed:
            "Transcription failed."
        case .polishFailed:
            "Text polish failed."
        case .pasteFailed:
            "Could not paste text into the active application."
        case .configurationCorrupted:
            "Configuration file is corrupted and has been reset."
        case .noUsableAudio:
            "No usable audio was captured."
        case .recordingTooShort:
            "Recording was too short."
        case .engineNotReady:
            "Transcription engine is not ready."
        }
    }
}
