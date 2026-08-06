import Foundation

/// One redacted record per dictation attempt. Contains timings, sizes, and
/// categories only — never transcript text, audio, or clipboard content
/// (privacy contract §7/§11 and the operating prompt's reliability rules).
struct DictationRecord: Identifiable, Equatable, Sendable {
    enum Result: String, Sendable {
        case completed
        case rejectedTooShort
        case rejectedNoUsableAudio
        case transcriptionFailed
        case emptyTranscript
        case pasteFailed
        case recorderFailed
        case cancelled
    }

    let id = UUID()
    let startedAt: Date
    let engineID: TranscriptionEngineID?
    let result: Result
    /// Captured audio length in seconds (0 when recording never produced audio).
    let audioDurationSeconds: Double
    /// Hotkey release → transcript available. Nil when transcription never ran.
    let releaseToTranscriptMs: Int?
    /// Hotkey release → paste completed. Nil when paste never ran.
    let releaseToPasteMs: Int?
    /// Transcript length in characters (never the content itself).
    let transcriptCharacters: Int?
    /// Whether the dictation hit the 120 s cap.
    let hitMaxDuration: Bool

    static func == (lhs: DictationRecord, rhs: DictationRecord) -> Bool {
        lhs.id == rhs.id
    }
}

/// In-memory, session-only store of the latest dictation records plus
/// aggregate timings. Nothing is persisted to disk (operating prompt:
/// "Store only aggregate timing/counter data in memory during a session").
@MainActor
@Observable
final class DictationMetrics {
    static let capacity = 20

    private(set) var records: [DictationRecord] = []
    private(set) var totalAttempts = 0
    private(set) var totalCompleted = 0

    func record(_ record: DictationRecord) {
        totalAttempts += 1
        if record.result == .completed {
            totalCompleted += 1
        }
        records.insert(record, at: 0)
        if records.count > Self.capacity {
            records.removeLast(records.count - Self.capacity)
        }
    }

    /// Median release→paste over the retained completed records.
    var medianReleaseToPasteMs: Int? {
        percentileReleaseToPaste(0.5)
    }

    /// p95 release→paste over the retained completed records.
    var p95ReleaseToPasteMs: Int? {
        percentileReleaseToPaste(0.95)
    }

    private func percentileReleaseToPaste(_ p: Double) -> Int? {
        let values = records.compactMap(\.releaseToPasteMs).sorted()
        guard !values.isEmpty else { return nil }
        let rank = Int((Double(values.count - 1) * p).rounded())
        return values[rank]
    }
}
