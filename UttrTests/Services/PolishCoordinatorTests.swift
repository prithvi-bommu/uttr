import Foundation
import Testing
@testable import Uttr

@Suite("PolishCoordinator")
struct PolishCoordinatorTests {

    // MARK: - Test doubles

    private actor DelayedPolisher: TextPolisher {
        let result: String
        let delayMs: UInt64
        let error: Error?
        private(set) var callCount = 0

        init(result: String = "polished", delayMs: UInt64 = 0, error: Error? = nil) {
            self.result = result
            self.delayMs = delayMs
            self.error = error
        }

        func polish(_ transcript: String) async throws -> String {
            callCount += 1
            if delayMs > 0 {
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            if let error { throw error }
            return result
        }

        func testConnection() async throws -> PolishTestResult { .success }
    }

    // MARK: - AI response before deadline → paste polished text

    @Test("AI response arrives before deadline: paste polished text")
    func aiBeforeDeadline() async {
        let polisher = DelayedPolisher(result: "clean text", delayMs: 10)
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "raw text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "clean text")
        #expect(result.outcome == .aiSuccess)
        #expect(result.aiRequestStartedAt != nil)
        #expect(result.aiResponseReceivedAt != nil)
    }

    // MARK: - AI response after deadline → paste local text, ignore late response

    @Test("AI response arrives after deadline: paste local text")
    func aiAfterDeadline() async {
        let polisher = DelayedPolisher(result: "late polished", delayMs: 500)
        let coordinator = PolishCoordinator(budgetMs: 50)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .deadlineFallback)
        #expect(result.aiRequestStartedAt != nil)
        #expect(result.aiResponseReceivedAt == nil)
    }

    // MARK: - Network failure → paste local text

    @Test("provider network failure: paste local text")
    func providerFailure() async {
        let polisher = DelayedPolisher(
            error: URLError(.notConnectedToInternet))
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .providerFailure)
    }

    // MARK: - Malformed response → paste local text

    @Test("AI returns empty string: paste local text")
    func emptyAiResponse() async {
        let polisher = DelayedPolisher(result: "   ")
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .invalidResponse)
    }

    @Test("AI returns framing preamble: paste local text")
    func framingPreamble() async {
        let polisher = DelayedPolisher(result: "Here is the cleaned up text: hello world")
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "hello world",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "hello world")
        #expect(result.outcome == .invalidResponse)
    }

    @Test("AI returns vastly expanded text: paste local text")
    func boundedExpansion() async {
        let longResponse = String(repeating: "word ", count: 500)
        let polisher = DelayedPolisher(result: longResponse)
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "short",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "short")
        #expect(result.outcome == .invalidResponse)
    }

    // MARK: - Missing API key / no polisher → paste local text

    @Test("no cloud polisher configured: paste local text with noPolisher outcome")
    func noPolisher() async {
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: nil,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .noPolisher)
        #expect(result.aiRequestStartedAt == nil)
    }

    // MARK: - Zero budget → skip without sending request

    @Test("zero budget: skip polish, paste local text")
    func zeroBudget() async {
        let polisher = DelayedPolisher(result: "should not run")
        let coordinator = PolishCoordinator(budgetMs: 0)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .skippedNoTime)
        #expect(result.aiRequestStartedAt == nil)
    }

    // MARK: - AI response fails hallucination filter

    @Test("AI returns known hallucination: paste local text")
    func hallucinationFiltered() async {
        let polisher = DelayedPolisher(result: "[BLANK_AUDIO]")
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .invalidResponse)
    }

    // MARK: - HTTP error → paste local text

    @Test("cloud polish HTTP error: paste local text")
    func httpError() async {
        let polisher = DelayedPolisher(
            error: CloudPolishError.requestFailed(status: 500))
        let coordinator = PolishCoordinator(budgetMs: 500)

        let result = await coordinator.polish(
            localText: "local text",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.text == "local text")
        #expect(result.outcome == .providerFailure)
    }

    // MARK: - Timeline populated correctly

    @Test("successful polish populates full timeline")
    func timelinePopulated() async {
        let polisher = DelayedPolisher(result: "polished", delayMs: 10)
        let coordinator = PolishCoordinator(budgetMs: 500)
        let before = Date()

        let result = await coordinator.polish(
            localText: "raw",
            cloudPolisher: polisher,
            sessionID: UUID())

        #expect(result.outcome == .aiSuccess)
        #expect(result.aiRequestStartedAt! >= before)
        #expect(result.aiResponseReceivedAt! >= result.aiRequestStartedAt!)
    }
}

@Suite("Adaptive polish integration (DictationController)")
@MainActor
struct AdaptivePolishIntegrationTests {

    private struct StubPolisher: TextPolisher {
        let result: String
        func polish(_ transcript: String) async throws -> String { result }
        func testConnection() async throws -> PolishTestResult { .success }
    }

    private actor SlowPolisher: TextPolisher {
        let result: String
        let delayMs: UInt64

        init(result: String, delayMs: UInt64) {
            self.result = result
            self.delayMs = delayMs
        }

        func polish(_ transcript: String) async throws -> String {
            try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            return result
        }
        func testConnection() async throws -> PolishTestResult { .success }
    }

    private actor FailingPolisher: TextPolisher {
        func polish(_ transcript: String) async throws -> String {
            throw URLError(.notConnectedToInternet)
        }
        func testConnection() async throws -> PolishTestResult { .unavailable }
    }

    private struct Harness {
        let appState: AppState
        let recorder: MockAudioRecorder
        let factory: MockEngineFactory
        let coordinator: TranscriptionCoordinator
        let pasteService: MockPasteService
        let metrics: DictationMetrics
        let controller: DictationController
    }

    private func makeHarness(
        localPolisher: TextPolisher? = nil,
        cloudPolisher: TextPolisher? = nil,
        budgetMs: Int = 250
    ) -> Harness {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false))
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        let pasteService = MockPasteService()
        let metrics = DictationMetrics()
        let controller = DictationController(
            appState: appState,
            recorder: recorder,
            coordinator: coordinator,
            pasteService: pasteService,
            clock: MockDictationClock(),
            metrics: metrics,
            localPolisherProvider: { localPolisher },
            cloudPolisherProvider: { cloudPolisher },
            polishCoordinatorProvider: {
                PolishCoordinator(budgetMs: budgetMs)
            })
        return Harness(appState: appState, recorder: recorder, factory: factory,
                       coordinator: coordinator, pasteService: pasteService,
                       metrics: metrics, controller: controller)
    }

    private func runDictation(_ h: Harness) async {
        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()
        await waitUntil { h.appState.dictationState == .idle && !h.pasteService.pastedTexts.isEmpty }
    }

    // MARK: - Fast cloud polish pastes polished text

    @Test("fast cloud polish: paste polished text")
    func fastCloudPolish() async {
        let h = makeHarness(
            localPolisher: StubPolisher(result: "local cleaned"),
            cloudPolisher: StubPolisher(result: "cloud cleaned"),
            budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw text"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts == ["cloud cleaned"])
        #expect(h.appState.lastTranscript == "cloud cleaned")
        #expect(h.metrics.records.first?.polishOutcome == .aiSuccess)
    }

    // MARK: - Slow cloud polish falls back to local-cleaned text

    @Test("slow cloud polish: paste local-cleaned text")
    func slowCloudPolish() async {
        let h = makeHarness(
            localPolisher: StubPolisher(result: "local cleaned"),
            cloudPolisher: SlowPolisher(result: "late result", delayMs: 500),
            budgetMs: 50)
        h.factory.whisperEngine.transcriptToReturn = "raw text"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts == ["local cleaned"])
        #expect(h.metrics.records.first?.polishOutcome == .deadlineFallback)
    }

    // MARK: - Provider failure falls back to local-cleaned text

    @Test("provider failure: paste local-cleaned text")
    func providerFailureFallback() async {
        let h = makeHarness(
            localPolisher: StubPolisher(result: "local cleaned"),
            cloudPolisher: FailingPolisher(),
            budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw text"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts == ["local cleaned"])
        #expect(h.metrics.records.first?.polishOutcome == .providerFailure)
    }

    // MARK: - No cloud polisher → paste local-cleaned text

    @Test("no cloud polisher: paste local-cleaned text")
    func noCloudPolisher() async {
        let h = makeHarness(
            localPolisher: StubPolisher(result: "local cleaned"),
            cloudPolisher: nil,
            budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw text"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts == ["local cleaned"])
        #expect(h.metrics.records.first?.polishOutcome == .noPolisher)
    }

    // MARK: - No polishers at all → paste raw transcript

    @Test("no polishers: paste raw transcript")
    func noPolishers() async {
        let h = makeHarness(budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw text"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts == ["raw text"])
    }

    // MARK: - Paste executes exactly once on every path

    @Test("paste executes exactly once on success path")
    func pasteExactlyOnceSuccess() async {
        let h = makeHarness(
            cloudPolisher: StubPolisher(result: "polished"),
            budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts.count == 1)
    }

    @Test("paste executes exactly once on fallback path")
    func pasteExactlyOnceFallback() async {
        let h = makeHarness(
            cloudPolisher: SlowPolisher(result: "late", delayMs: 500),
            budgetMs: 50)
        h.factory.whisperEngine.transcriptToReturn = "raw"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts.count == 1)
    }

    @Test("paste executes exactly once on failure path")
    func pasteExactlyOnceFailure() async {
        let h = makeHarness(
            cloudPolisher: FailingPolisher(),
            budgetMs: 500)
        h.factory.whisperEngine.transcriptToReturn = "raw"

        await runDictation(h)

        #expect(h.pasteService.pastedTexts.count == 1)
    }

    // MARK: - Metrics timeline recorded

    @Test("metrics record polish outcome and configured budget")
    func metricsRecorded() async {
        let h = makeHarness(
            cloudPolisher: StubPolisher(result: "polished"),
            budgetMs: 250)
        h.factory.whisperEngine.transcriptToReturn = "raw"

        await runDictation(h)

        let record = h.metrics.records.first!
        #expect(record.polishOutcome == .aiSuccess)
        #expect(record.configuredBudgetMs == 250)
        #expect(record.releaseToTranscriptMs != nil)
        #expect(record.releaseToPasteMs != nil)
    }

    // MARK: - Cancellation assigns new session ID

    @Test("escape cancellation prevents stale paste from prior session")
    func cancelPreventsStale() async {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false))
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        let pasteService = MockPasteService()
        let metrics = DictationMetrics()
        let controller = DictationController(
            appState: appState,
            recorder: recorder,
            coordinator: coordinator,
            pasteService: pasteService,
            clock: MockDictationClock(),
            metrics: metrics,
            cloudPolisherProvider: { StubPolisher(result: "polished") },
            polishCoordinatorProvider: {
                PolishCoordinator(budgetMs: 500)
            })
        factory.whisperEngine.transcriptToReturn = "first dictation"

        // Start and complete a normal dictation
        appState.handle(.hotkeyDown)
        controller.recordingStarted()
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()
        await waitUntil { !pasteService.pastedTexts.isEmpty }

        #expect(pasteService.pastedTexts.count == 1)

        // Cancel a second dictation — should not paste anything
        factory.whisperEngine.transcriptToReturn = "second dictation"
        appState.handle(.hotkeyDown)
        controller.recordingStarted()
        await waitUntil { recorder.startCount == 2 }
        appState.handle(.escapePressed)
        controller.recordingCancelled()
        await waitUntil { recorder.cancelCount == 1 }

        // Still only one paste from the first dictation
        #expect(pasteService.pastedTexts.count == 1)
    }
}
