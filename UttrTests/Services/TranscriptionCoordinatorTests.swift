import Foundation
import Testing
@testable import Uttr

@Suite("TranscriptionCoordinator")
@MainActor
struct TranscriptionCoordinatorTests {

    // MARK: - Engine selection (spec §8)

    @Test("whisperKit selection always resolves to WhisperKit")
    func explicitWhisperKit() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: MockTranscriptionEngine(id: .systemSpeech)),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .whisperKit) == .whisperKit)
    }

    @Test("automatic resolves to WhisperKit even when System Speech is available")
    func automaticUsesWhisperKit() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: MockTranscriptionEngine(id: .systemSpeech)),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .whisperKit)
    }

    @Test("automatic falls back to WhisperKit when system speech unavailable")
    func automaticFallsBack() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .whisperKit)
    }

    @Test("systemSpeech selection falls back to WhisperKit when unavailable")
    func systemSpeechFallsBack() {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        #expect(coordinator.resolveEngineID(selection: .systemSpeech) == .whisperKit)
    }

    @Test("availability true but no engine built yet still resolves WhisperKit")
    func availabilityWithoutEngine() {
        // macOS 26 runtime but M5 engine not implemented -> WhisperKit
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(systemEngine: nil),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: true)
        )
        #expect(coordinator.resolveEngineID(selection: .automatic) == .whisperKit)
    }

    // MARK: - Configuration and preparation

    @Test("configure prepares the selected whisper model in background")
    func configurePrepares() async {
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )

        coordinator.configure(selection: .whisperKit, whisperModel: "medium.en")
        #expect(factory.whisperModelsRequested == ["medium.en"])
        #expect(coordinator.activeEngineID == .whisperKit)

        // Preparation completes asynchronously.
        await waitUntil { coordinator.preparationState == .ready }
        #expect(factory.whisperEngine.prepareCount == 1)
    }

    @Test("preparation failure surfaces as failed state")
    func prepareFailureSurfaces() async {
        let factory = MockEngineFactory()
        factory.whisperEngine.prepareError = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "download failed"])
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )

        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        await waitUntil {
            if case .failed = coordinator.preparationState { return true }
            return false
        }
        #expect(coordinator.preparationState == .failed("download failed"))
    }

    @Test("transcribe waits for in-flight preparation then delegates")
    func transcribeAfterPrepare() async throws {
        let factory = MockEngineFactory()
        factory.whisperEngine.transcriptToReturn = "dictated words"
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")

        let audio = CapturedAudio(samples: [Float](repeating: 0.2, count: 16_000), sampleRate: 16_000)
        let text = try await coordinator.transcribe(audio)

        #expect(text == "dictated words")
        #expect(factory.whisperEngine.lastAudio == audio)
    }

    @Test("transcribe without configuration throws engineNotReady")
    func transcribeUnconfigured() async {
        let coordinator = TranscriptionCoordinator(
            factory: MockEngineFactory(),
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        let audio = CapturedAudio(samples: [0.1], sampleRate: 16_000)
        await #expect(throws: UttrError.self) {
            _ = try await coordinator.transcribe(audio)
        }
    }

    @Test("reconfiguring with a new model rebuilds the engine")
    func reconfigureRebuilds() async {
        let factory = MockEngineFactory()
        let coordinator = TranscriptionCoordinator(
            factory: factory,
            availability: MockSystemSpeechAvailability(isSystemSpeechAvailable: false)
        )
        coordinator.configure(selection: .whisperKit, whisperModel: "small.en")
        coordinator.configure(selection: .whisperKit, whisperModel: "tiny.en")
        #expect(factory.whisperModelsRequested == ["small.en", "tiny.en"])
    }
}

/// Polls a condition on the main actor until true or a short timeout elapses.
@MainActor
func waitUntil(
    timeout: TimeInterval = 2,
    _ condition: @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
}
