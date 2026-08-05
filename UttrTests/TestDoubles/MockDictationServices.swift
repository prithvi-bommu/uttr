import Foundation
@testable import Uttr

/// Scriptable recorder double. All knobs are set before use; recorded calls
/// are inspected after.
final class MockAudioRecorder: AudioRecording, @unchecked Sendable {
    private let lock = NSLock()

    // Scripting
    var startError: Error?
    var audioToReturn = CapturedAudio(
        samples: [Float](repeating: 0.5, count: 16_000),
        sampleRate: 16_000
    )

    // Recorded interactions
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var cancelCount = 0

    func startRecording() async throws {
        let error: Error? = lock.withLock {
            startCount += 1
            return startError
        }
        if let error { throw error }
    }

    func stopRecording() async -> CapturedAudio {
        lock.withLock {
            stopCount += 1
            return audioToReturn
        }
    }

    func cancelRecording() async {
        lock.withLock { cancelCount += 1 }
    }
}

/// Scriptable transcription engine double.
final class MockTranscriptionEngine: TranscriptionEngine, @unchecked Sendable {
    let id: TranscriptionEngineID

    private let lock = NSLock()
    var prepareError: Error?
    var transcribeError: Error?
    var transcriptToReturn = "hello world"

    private(set) var prepareCount = 0
    private(set) var transcribeCount = 0
    private(set) var cancelCount = 0
    private(set) var lastAudio: CapturedAudio?

    init(id: TranscriptionEngineID = .whisperKit) {
        self.id = id
    }

    func prepare() async throws {
        let error: Error? = lock.withLock {
            prepareCount += 1
            return prepareError
        }
        if let error { throw error }
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        let (error, text): (Error?, String) = lock.withLock {
            transcribeCount += 1
            lastAudio = audio
            return (transcribeError, transcriptToReturn)
        }
        if let error { throw error }
        return text
    }

    func cancelCurrentWork() async {
        lock.withLock { cancelCount += 1 }
    }
}

/// Factory double handing back preconfigured engines.
final class MockEngineFactory: TranscriptionEngineFactory, @unchecked Sendable {
    let whisperEngine: MockTranscriptionEngine
    let systemEngine: MockTranscriptionEngine?

    private(set) var whisperModelsRequested: [String] = []
    private let lock = NSLock()

    init(
        whisperEngine: MockTranscriptionEngine = MockTranscriptionEngine(id: .whisperKit),
        systemEngine: MockTranscriptionEngine? = nil
    ) {
        self.whisperEngine = whisperEngine
        self.systemEngine = systemEngine
    }

    func makeWhisperKitEngine(model: String) -> TranscriptionEngine {
        lock.lock()
        whisperModelsRequested.append(model)
        lock.unlock()
        return whisperEngine
    }

    func makeSystemSpeechEngine() -> TranscriptionEngine? {
        systemEngine
    }
}

struct MockSystemSpeechAvailability: SystemSpeechAvailability {
    var isSystemSpeechAvailable: Bool
}

/// Scriptable WhisperKit client double for WhisperKitEngine tests.
final class MockWhisperClient: WhisperTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    var loadError: Error?
    var transcribeError: Error?
    var textToReturn = "  transcribed text \n"

    private(set) var loadedModels: [String] = []
    private(set) var receivedSamples: [[Float]] = []

    func loadModel(_ model: String) async throws {
        let error: Error? = lock.withLock {
            loadedModels.append(model)
            return loadError
        }
        if let error { throw error }
    }

    func transcribe(samples: [Float]) async throws -> String {
        let (error, text): (Error?, String) = lock.withLock {
            receivedSamples.append(samples)
            return (transcribeError, textToReturn)
        }
        if let error { throw error }
        return text
    }
}

/// Records pasted text; scriptable success/failure.
final class MockPasteService: PasteServicing, @unchecked Sendable {
    private let lock = NSLock()
    var succeed = true
    private(set) var pastedTexts: [String] = []

    func paste(_ text: String) async -> Bool {
        lock.withLock {
            pastedTexts.append(text)
            return succeed
        }
    }
}

/// Clock double: `sleep` suspends until the test explicitly fires or cancels it.
final class MockDictationClock: DictationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var sleepCount = 0

    func sleep(for duration: TimeInterval) async throws {
        lock.withLock { sleepCount += 1 }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { continuations.append(continuation) }
        }
    }

    /// Fires all pending sleeps as if the duration elapsed.
    func fire() {
        lock.lock()
        let pending = continuations
        continuations = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}
