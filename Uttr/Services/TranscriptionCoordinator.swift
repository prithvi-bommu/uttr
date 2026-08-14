import Foundation
import OSLog

/// Answers "is System Speech available here?" — injectable so unit tests can
/// simulate macOS 26+ without running on it.
protocol SystemSpeechAvailability: Sendable {
    var isSystemSpeechAvailable: Bool { get }
}

struct RuntimeSystemSpeechAvailability: SystemSpeechAvailability {
    var isSystemSpeechAvailable: Bool {
        RuntimeSystemSpeechClient.isAvailable
    }
}

/// Builds engines for the coordinator; injectable so tests can hand back mocks.
protocol TranscriptionEngineFactory: Sendable {
    func makeWhisperKitEngine(model: String) -> TranscriptionEngine
    func makeSystemSpeechEngine() -> TranscriptionEngine?
}

struct DefaultTranscriptionEngineFactory: TranscriptionEngineFactory {
    func makeWhisperKitEngine(model: String) -> TranscriptionEngine {
        WhisperKitEngine(model: model)
    }

    func makeSystemSpeechEngine() -> TranscriptionEngine? {
        guard RuntimeSystemSpeechClient.isAvailable else { return nil }
        return SpeechAnalyzerEngine()
    }
}

/// Selects and owns the active `TranscriptionEngine` per spec §8:
/// - `automatic`: WhisperKit. System Speech remains an explicit opt-in while
///   its runtime integration is validated on macOS 26.
/// - `systemSpeech`: System Speech, falling back to WhisperKit per dictation
/// - `whisperKit`: always WhisperKit
/// Prepares the active engine asynchronously, republishes preparation state
/// for Settings, and invalidates on engine/model change.
@MainActor
@Observable
final class TranscriptionCoordinator {
    private(set) var preparationState: ModelPreparationState = .notPrepared
    private(set) var activeEngineID: TranscriptionEngineID?

    @ObservationIgnored private var activeEngine: TranscriptionEngine?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private let factory: TranscriptionEngineFactory
    @ObservationIgnored private let availability: SystemSpeechAvailability
    @ObservationIgnored private let logger = Logger(subsystem: "com.uttr.app", category: "transcription")

    init(
        factory: TranscriptionEngineFactory = DefaultTranscriptionEngineFactory(),
        availability: SystemSpeechAvailability = RuntimeSystemSpeechAvailability()
    ) {
        self.factory = factory
        self.availability = availability
    }

    /// Resolves which engine the current settings select. Pure, synchronous —
    /// unit-testable without any engine work.
    func resolveEngineID(
        selection: TranscriptionEngineSelection
    ) -> TranscriptionEngineID {
        switch selection {
        case .whisperKit:
            return .whisperKit
        case .automatic:
            return .whisperKit
        case .systemSpeech:
            if availability.isSystemSpeechAvailable, factory.makeSystemSpeechEngine() != nil {
                return .systemSpeech
            }
            logger.info("System Speech selected but unavailable — falling back to WhisperKit")
            return .whisperKit
        }
    }

    /// Applies settings: builds the selected engine if it changed and kicks off
    /// background preparation. Never blocks the caller.
    func configure(selection: TranscriptionEngineSelection, whisperModel: String) {
        let resolved = resolveEngineID(selection: selection)

        let engine: TranscriptionEngine
        switch resolved {
        case .systemSpeech:
            guard let systemEngine = factory.makeSystemSpeechEngine() else {
                configure(selection: .whisperKit, whisperModel: whisperModel)
                return
            }
            engine = systemEngine
        case .whisperKit:
            engine = factory.makeWhisperKitEngine(model: whisperModel)
        }

        prepareTask?.cancel()
        activeEngine = engine
        activeEngineID = resolved
        preparationState = .preparing

        prepareTask = Task { [weak self] in
            do {
                try await engine.prepare()
                guard !Task.isCancelled else { return }
                self?.preparationState = .ready
            } catch {
                guard !Task.isCancelled else { return }
                self?.preparationState = .failed(error.localizedDescription)
                self?.logger.error("Engine preparation failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Transcribes captured audio with the active engine.
    /// Throws `UttrError.engineNotReady` when no engine is configured/ready.
    func transcribe(_ audio: CapturedAudio) async throws -> String {
        guard let engine = activeEngine else { throw UttrError.engineNotReady }
        if preparationState != .ready {
            // A dictation can race ahead of first-time preparation; wait for
            // the in-flight prepare rather than failing the user's dictation.
            await prepareTask?.value
            guard preparationState == .ready else { throw UttrError.engineNotReady }
        }
        return try await engine.transcribe(audio)
    }

    func cancelCurrentWork() async {
        await activeEngine?.cancelCurrentWork()
    }
}
