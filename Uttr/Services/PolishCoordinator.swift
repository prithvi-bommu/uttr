import Foundation
import OSLog

enum PolishOutcome: String, Sendable {
    case aiSuccess
    case deadlineFallback
    case skippedNoTime
    case providerFailure
    case invalidResponse
    case cancelled
    case noPolisher
}

struct PolishResult: Sendable {
    let text: String
    let outcome: PolishOutcome
    let aiRequestStartedAt: Date?
    let aiResponseReceivedAt: Date?
}

struct PolishCoordinator: Sendable {
    static let defaultBudgetMs: Int = 250

    let budgetMs: Int
    private let logger = Logger(subsystem: "com.uttr.app", category: "polish")

    init(budgetMs: Int = Self.defaultBudgetMs) {
        self.budgetMs = budgetMs
    }

    func polish(
        localText: String,
        cloudPolisher: TextPolisher?,
        sessionID: UUID
    ) async -> PolishResult {
        guard let polisher = cloudPolisher else {
            return PolishResult(text: localText, outcome: .noPolisher,
                                aiRequestStartedAt: nil, aiResponseReceivedAt: nil)
        }

        guard budgetMs > 0 else {
            return PolishResult(text: localText, outcome: .skippedNoTime,
                                aiRequestStartedAt: nil, aiResponseReceivedAt: nil)
        }

        return await racePolishAgainstDeadline(polisher: polisher, localText: localText)
    }

    // MARK: - Race

    private func racePolishAgainstDeadline(
        polisher: TextPolisher, localText: String
    ) async -> PolishResult {
        let aiStartedAt = Date()
        let polishTask = Task<String, Error> { try await polisher.polish(localText) }
        let timerTask = Task<Void, Never> {
            try? await Task.sleep(nanoseconds: UInt64(budgetMs) * 1_000_000)
        }

        return await withTaskGroup(of: PolishRaceResult.self) { group in
            group.addTask {
                do {
                    let polished = try await polishTask.value
                    return .polished(polished, receivedAt: Date())
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .failed(error)
                }
            }
            group.addTask {
                await timerTask.value
                return .timeout
            }

            guard let first = await group.next() else {
                return fallback(localText, aiStartedAt: aiStartedAt, outcome: .cancelled)
            }

            return resolveRace(first, polishTask: polishTask, timerTask: timerTask,
                               localText: localText, aiStartedAt: aiStartedAt)
        }
    }

    // MARK: - Resolution

    private func resolveRace(
        _ first: PolishRaceResult,
        polishTask: Task<String, Error>,
        timerTask: Task<Void, Never>,
        localText: String,
        aiStartedAt: Date
    ) -> PolishResult {
        switch first {
        case .polished(let text, let receivedAt):
            polishTask.cancel()
            timerTask.cancel()
            return resolvePolished(text, localText: localText,
                                   aiStartedAt: aiStartedAt, receivedAt: receivedAt)

        case .timeout:
            polishTask.cancel()
            logger.info("AI polish deadline (\(budgetMs)ms) exceeded — using local text")
            return fallback(localText, aiStartedAt: aiStartedAt, outcome: .deadlineFallback)

        case .failed(let error):
            timerTask.cancel()
            logger.error("AI polish failed: \(error.localizedDescription, privacy: .public)")
            return PolishResult(text: localText, outcome: .providerFailure,
                                aiRequestStartedAt: aiStartedAt, aiResponseReceivedAt: Date())

        case .cancelled:
            timerTask.cancel()
            return fallback(localText, aiStartedAt: aiStartedAt, outcome: .cancelled)
        }
    }

    private func resolvePolished(
        _ text: String, localText: String,
        aiStartedAt: Date, receivedAt: Date
    ) -> PolishResult {
        if let validated = validate(text, original: localText) {
            return PolishResult(text: validated, outcome: .aiSuccess,
                                aiRequestStartedAt: aiStartedAt, aiResponseReceivedAt: receivedAt)
        }
        logger.info("AI polish response failed validation — using local text")
        return PolishResult(text: localText, outcome: .invalidResponse,
                            aiRequestStartedAt: aiStartedAt, aiResponseReceivedAt: receivedAt)
    }

    private func fallback(
        _ localText: String, aiStartedAt: Date, outcome: PolishOutcome
    ) -> PolishResult {
        PolishResult(text: localText, outcome: outcome,
                     aiRequestStartedAt: aiStartedAt, aiResponseReceivedAt: nil)
    }

    // MARK: - Validation

    private func validate(_ polished: String, original: String) -> String? {
        let trimmed = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expansionLimit = max(original.count * 3, 200)
        guard trimmed.count <= expansionLimit else { return nil }

        let lower = trimmed.lowercased()
        let framingPrefixes = [
            "here is", "here's", "sure,", "certainly,",
            "of course,", "i've cleaned", "cleaned up",
        ]
        for prefix in framingPrefixes where lower.hasPrefix(prefix) {
            return nil
        }

        let hallucinationCleaned = HallucinationFilter.clean(trimmed)
        guard !hallucinationCleaned.isEmpty else { return nil }

        return trimmed
    }
}

private enum PolishRaceResult: Sendable {
    case polished(String, receivedAt: Date)
    case timeout
    case failed(Error)
    case cancelled
}
