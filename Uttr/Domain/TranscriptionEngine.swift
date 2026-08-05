import Foundation

enum TranscriptionEngineID: String, Sendable {
    case systemSpeech
    case whisperKit
}

/// In-memory captured audio. Mono Float32 PCM at 16 kHz — the exact format
/// WhisperKit's `transcribe(audioArrays:)` consumes (ADR-004). There is
/// deliberately no file URL: audio never touches disk in the dictation path.
struct CapturedAudio: Sendable, Equatable {
    static let requiredSampleRate: Double = 16_000

    let samples: [Float]
    let sampleRate: Double

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
    }
}

protocol TranscriptionEngine: Sendable {
    var id: TranscriptionEngineID { get }
    func prepare() async throws
    func transcribe(_ audio: CapturedAudio) async throws -> String
    func cancelCurrentWork() async
}

/// Observable download/readiness state for the active local model,
/// surfaced in Transcription settings.
enum ModelPreparationState: Equatable, Sendable {
    case notPrepared
    case preparing
    case ready
    case failed(String)

    var statusText: String {
        switch self {
        case .notPrepared: "Not downloaded"
        case .preparing: "Downloading / preparing…"
        case .ready: "Ready"
        case .failed(let message): "Failed: \(message)"
        }
    }
}
