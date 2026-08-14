import Foundation

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
    let audioDurationSeconds: Double
    let hitMaxDuration: Bool

    // MARK: - Full pipeline timeline (ms, nil when stage didn't run)

    let releaseToTranscriptMs: Int?
    let transcriptToLocalCleanMs: Int?
    let localCleanToAiRequestMs: Int?
    let aiRequestToResponseMs: Int?
    let responseToPasteMs: Int?
    let releaseToPasteMs: Int?

    // MARK: - Polish details

    let polishOutcome: PolishOutcome?
    let polisherSelected: String?
    let configuredBudgetMs: Int?
    let transcriptCharacters: Int?

    static func == (lhs: DictationRecord, rhs: DictationRecord) -> Bool {
        lhs.id == rhs.id
    }
}

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

    // MARK: - Release-to-paste percentiles

    var medianReleaseToPasteMs: Int? { percentileReleaseToPaste(0.5) }
    var p95ReleaseToPasteMs: Int? { percentileReleaseToPaste(0.95) }
    var p99ReleaseToPasteMs: Int? { percentileReleaseToPaste(0.99) }

    private func percentileReleaseToPaste(_ p: Double) -> Int? {
        let values = records
            .filter { $0.result == .completed }
            .compactMap(\.releaseToPasteMs)
            .sorted()
        guard !values.isEmpty else { return nil }
        let rank = Int((Double(values.count - 1) * p).rounded())
        return values[rank]
    }

    // MARK: - Polish outcome rates

    var fallbackRate: Double? {
        rateOf(outcomes: [.deadlineFallback])
    }

    var providerFailureRate: Double? {
        rateOf(outcomes: [.providerFailure])
    }

    var validationRejectionRate: Double? {
        rateOf(outcomes: [.invalidResponse])
    }

    private func rateOf(outcomes: Set<PolishOutcome>) -> Double? {
        let polished = records.filter { $0.polishOutcome != nil && $0.polishOutcome != .noPolisher }
        guard !polished.isEmpty else { return nil }
        let matching = polished.filter { outcomes.contains($0.polishOutcome!) }
        return Double(matching.count) / Double(polished.count)
    }
}
