import Foundation
import Testing
@testable import Uttr

@Suite("DictationController")
@MainActor
struct DictationControllerTests {

    struct Harness {
        let appState: AppState
        let recorder: MockAudioRecorder
        let factory: MockEngineFactory
        let coordinator: TranscriptionCoordinator
        let pasteService: MockPasteService
        let clock: MockDictationClock
        let controller: DictationController
    }

    @MainActor
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
        let clock = MockDictationClock()
        let controller = DictationController(
            appState: appState,
            recorder: recorder,
            coordinator: coordinator,
            pasteService: pasteService,
            clock: clock
        )
        return Harness(
            appState: appState, recorder: recorder, factory: factory,
            coordinator: coordinator, pasteService: pasteService,
            clock: clock, controller: controller)
    }

    // MARK: - Happy path (M3 acceptance: dictation reaches paste-service mock)

    @Test("full dictation: record -> transcribe -> paste mock -> idle")
    func happyPath() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcriptToReturn = "hello from dictation"

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }

        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle && !h.pasteService.pastedTexts.isEmpty }
        #expect(h.pasteService.pastedTexts == ["hello from dictation"])
        #expect(h.appState.lastTranscript == "hello from dictation")
        #expect(h.recorder.stopCount == 1)
    }

    // MARK: - Rejection paths (M3 acceptance: short/empty audio does not paste)

    @Test("too-short audio returns to idle without paste")
    func shortAudioNoPaste() async {
        let h = makeHarness()
        h.recorder.audioToReturn = CapturedAudio(
            samples: [Float](repeating: 0.5, count: 800), // 50 ms
            sampleRate: 16_000)

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle }
        #expect(h.appState.dictationState == .idle) // regression: was stuck in .transcribing
        #expect(h.pasteService.pastedTexts.isEmpty)
        #expect(h.factory.whisperEngine.transcribeCount == 0)
    }

    @Test("silent audio returns to idle without paste")
    func silentAudioNoPaste() async {
        let h = makeHarness()
        h.recorder.audioToReturn = CapturedAudio(
            samples: [Float](repeating: 0, count: 32_000), // 2 s of silence
            sampleRate: 16_000)

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle }
        #expect(h.appState.dictationState == .idle) // regression: was stuck in .transcribing
        #expect(h.pasteService.pastedTexts.isEmpty)
        #expect(h.factory.whisperEngine.transcribeCount == 0)
    }

    @Test("recorder start failure returns to idle")
    func startFailure() async {
        let h = makeHarness()
        h.recorder.startError = UttrError.audioCaptureFailed(
            underlying: NSError(domain: "test", code: 1))

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()

        await waitUntil { h.appState.dictationState == .idle }
        #expect(h.recorder.cancelCount == 1)
        #expect(h.pasteService.pastedTexts.isEmpty)
    }

    @Test("transcription failure returns to idle without paste")
    func transcriptionFailure() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcribeError = NSError(domain: "test", code: 2)

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle }
        #expect(h.appState.dictationState == .idle)
        #expect(h.pasteService.pastedTexts.isEmpty)
    }

    @Test("empty transcript does not paste")
    func emptyTranscriptNoPaste() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcriptToReturn = ""

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle }
        #expect(h.appState.dictationState == .idle)
        #expect(h.pasteService.pastedTexts.isEmpty)
    }

    @Test("escape cancels recording without transcription or paste")
    func escapeCancels() async {
        let h = makeHarness()

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }

        h.appState.handle(.escapePressed)
        h.controller.recordingCancelled()

        await waitUntil { h.recorder.cancelCount == 1 }
        #expect(h.appState.dictationState == .idle)
        #expect(h.factory.whisperEngine.transcribeCount == 0)
        #expect(h.pasteService.pastedTexts.isEmpty)
    }

    @Test("paste failure preserves text for clipboard recovery")
    func pasteFailure() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcriptToReturn = "kept text"
        h.pasteService.succeed = false

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.recorder.startCount == 1 }
        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()

        await waitUntil { h.appState.dictationState == .idle && !h.pasteService.pastedTexts.isEmpty }
        #expect(h.appState.pasteFailedText == "kept text")
    }

    @Test("local polish is applied to the transcript before pasting")
    func localPolishApplied() async {
        let appState = AppState()
        let recorder = MockAudioRecorder()
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false))
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        let pasteService = MockPasteService()
        let clock = MockDictationClock()
        let controller = DictationController(
            appState: appState, recorder: recorder, coordinator: coordinator,
            pasteService: pasteService, clock: clock,
            localPolisherProvider: { RuleBasedTextPolisher() })
        factory.whisperEngine.transcriptToReturn = "um hello hello world"

        appState.handle(.hotkeyDown)
        controller.recordingStarted()
        await waitUntil { recorder.startCount == 1 }
        appState.handle(.hotkeyUp)
        controller.recordingEnded()

        await waitUntil { appState.dictationState == .idle && !pasteService.pastedTexts.isEmpty }
        #expect(pasteService.pastedTexts == ["Hello world"])
        #expect(appState.lastTranscript == "Hello world")
    }

    // MARK: - Max duration (spec §8: stop at 120 s, transcribe what we have)

    @Test("max duration fires, stops recording, and transcribes")
    func maxDurationStops() async {
        let h = makeHarness()
        h.factory.whisperEngine.transcriptToReturn = "long dictation"

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.clock.sleepCount == 1 }

        h.clock.fire() // simulate 120 s elapsing while still recording

        await waitUntil { h.appState.dictationState == .idle && !h.pasteService.pastedTexts.isEmpty }
        #expect(h.pasteService.pastedTexts == ["long dictation"])
        #expect(h.recorder.stopCount == 1)
    }

    @Test("normal release cancels the max-duration timer")
    func releaseCancelsTimer() async {
        let h = makeHarness()

        h.appState.handle(.hotkeyDown)
        h.controller.recordingStarted()
        await waitUntil { h.clock.sleepCount == 1 }

        h.appState.handle(.hotkeyUp)
        h.controller.recordingEnded()
        await waitUntil { h.appState.dictationState == .idle }

        let stopsBefore = h.recorder.stopCount
        h.clock.fire() // late fire must be a no-op
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(h.recorder.stopCount == stopsBefore)
    }
}
