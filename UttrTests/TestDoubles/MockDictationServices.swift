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
        lock.lock()
        startCount += 1
        let error = startError
        lock.unlock()
        if let error { throw error }
    }

    func stopRecording() async -> CapturedAudio {
        lock.lock()
        stopCount += 1
        let audio = audioToReturn
        lock.unlock()
        return audio
    }

    func cancelRecording() async {
        lock.lock()
        cancelCount += 1
        lock.unlock()
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
        lock.lock()
        prepareCount += 1
        let error = prepareError
        lock.unlock()
        if let error { throw error }
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        lock.lock()
        transcribeCount += 1
        lastAudio = audio
        let error = transcribeError
        let text = transcriptToReturn
        lock.unlock()
        if let error { throw error }
        return text
    }

    func cancelCurrentWork() async {
        lock.lock()
        cancelCount += 1
        lock.unlock()
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
        lock.lock()
        loadedModels.append(model)
        let error = loadError
        lock.unlock()
        if let error { throw error }
    }

    func transcribe(samples: [Float]) async throws -> String {
        lock.lock()
        receivedSamples.append(samples)
        let error = transcribeError
        let text = textToReturn
        lock.unlock()
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
        lock.lock()
        pastedTexts.append(text)
        let result = succeed
        lock.unlock()
        return result
    }
}

/// Clock double: `sleep` suspends until the test explicitly fires or cancels it.
final class MockDictationClock: DictationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var sleepCount = 0

    func sleep(for duration: TimeInterval) async throws {
        lock.lock()
        sleepCount += 1
        lock.unlock()
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
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
