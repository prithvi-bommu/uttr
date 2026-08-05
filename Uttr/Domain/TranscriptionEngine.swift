import Foundation

enum TranscriptionEngineID: String, Sendable {
    case systemSpeech
    case whisperKit
}

struct CapturedAudio: Sendable {
    let samples: Data
    let sampleRate: Double
    let duration: TimeInterval
}

protocol TranscriptionEngine: Sendable {
    var id: TranscriptionEngineID { get }
    func prepare() async throws
    func transcribe(_ audio: CapturedAudio) async throws -> String
    func cancelCurrentWork() async
}
