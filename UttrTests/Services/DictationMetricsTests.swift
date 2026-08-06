import Foundation
import Testing
@testable import Uttr

@Suite("DictationMetrics")
@MainActor
struct DictationMetricsTests {

    private func record(
        result: DictationRecord.Result = .completed,
        releaseToPasteMs: Int? = 500
    ) -> DictationRecord {
        DictationRecord(
            startedAt: Date(),
            engineID: .whisperKit,
            result: result,
            audioDurationSeconds: 2.0,
            releaseToTranscriptMs: releaseToPasteMs.map { $0 - 100 },
            releaseToPasteMs: releaseToPasteMs,
            transcriptCharacters: 42,
            hitMaxDuration: false
        )
    }

    @Test("records newest-first and counts attempts/completions")
    func recordsAndCounts() {
        let metrics = DictationMetrics()
        metrics.record(record(result: .completed))
        metrics.record(record(result: .rejectedTooShort, releaseToPasteMs: nil))
        #expect(metrics.totalAttempts == 2)
        #expect(metrics.totalCompleted == 1)
        #expect(metrics.records.first?.result == .rejectedTooShort)
    }

    @Test("caps retained records at 20 without losing counters")
    func capsAtTwenty() {
        let metrics = DictationMetrics()
        for _ in 0..<25 {
            metrics.record(record())
        }
        #expect(metrics.records.count == DictationMetrics.capacity)
        #expect(metrics.totalAttempts == 25)
    }

    @Test("median and p95 computed over completed timings only")
    func percentiles() {
        let metrics = DictationMetrics()
        for ms in [100, 200, 300, 400, 1000] {
            metrics.record(record(releaseToPasteMs: ms))
        }
        metrics.record(record(result: .rejectedTooShort, releaseToPasteMs: nil)) // excluded
        #expect(metrics.medianReleaseToPasteMs == 300)
        #expect(metrics.p95ReleaseToPasteMs == 1000)
    }

    @Test("no timings yields nil aggregates")
    func emptyAggregates() {
        let metrics = DictationMetrics()
        #expect(metrics.medianReleaseToPasteMs == nil)
        #expect(metrics.p95ReleaseToPasteMs == nil)
    }
}

@Suite("DictationController metrics emission")
@MainActor
struct DictationControllerMetricsTests {

    struct Harness {
        let appState: AppState
        let recorder: MockAudioRecorder
        let factory: MockEngineFactory
        let pasteService: MockPasteService
        let metrics: DictationMetrics
        let controller: DictationController
    }

    private func makeHarness() -> Harness {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        let pasteService = MockPasteService()
        let metrics = DictationMetrics()
        let controller = DictationController(
            appState: appState,
            recorder: recorder,
            coordinator: coordinator,
            pasteService: pasteService,
            clock: MockDictationClock(),
            metrics: metrics
        )
        return Harness(appState: appState, recorder: recorder, factory: factory,
                       pasteService: pasteService, metrics: metrics, controller: controller)
    }

    @Test("completed dictation records timings and character count")
    func completedRecord() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcriptToReturn = "twelve chars"

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()
        await waitUntil { h.metrics.records.count == 1 }

        let record = h.metrics.records[0]
        #expect(record.result == .completed)
        #expect(record.transcriptCharacters == 12)
        #expect(record.releaseToTranscriptMs != nil)
        #expect(record.releaseToPasteMs != nil)
        #expect(record.engineID == .whisperKit)
        #expect(h.metrics.totalCompleted == 1)
    }

    @Test("too-short rejection records category without timings")
    func rejectionRecord() async {
        let h = makeHarness()
        h.recorder.audioToReturn = CapturedAudio(
            samples: [Float](repeating: 0.5, count: 800), sampleRate: 16_000)

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()
        await waitUntil { h.metrics.records.count == 1 }

        let record = h.metrics.records[0]
        #expect(record.result == .rejectedTooShort)
        #expect(record.releaseToPasteMs == nil)
        #expect(record.transcriptCharacters == nil)
        #expect(h.metrics.totalCompleted == 0)
    }

    @Test("escape cancel records cancelled")
    func cancelRecord() async {
        let h = makeHarness()
        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.escapePressed)
        h.controller.recordingCancelled()
        await waitUntil { h.metrics.records.count == 1 }
        #expect(h.metrics.records[0].result == .cancelled)
    }

    @Test("paste failure records pasteFailed with timings")
    func pasteFailureRecord() async {
        let h = makeHarness()
        h.pasteService.succeed = false

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()
        await waitUntil { h.metrics.records.count == 1 }

        #expect(h.metrics.records[0].result == .pasteFailed)
        #expect(h.metrics.records[0].releaseToPasteMs != nil)
    }
}
