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

/// Scriptable Apple System Speech client double.
final class MockSystemSpeechClient: SystemSpeechTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    var prepareError: Error?
    var transcribeError: Error?
    var textToReturn = "  system transcript \n"

    private(set) var prepareCount = 0
    private(set) var receivedAudio: [CapturedAudio] = []
    private(set) var cancelCount = 0

    func prepare() async throws {
        let error = lock.withLock {
            prepareCount += 1
            return prepareError
        }
        if let error { throw error }
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        let (error, text) = lock.withLock {
            receivedAudio.append(audio)
            return (transcribeError, textToReturn)
        }
        if let error { throw error }
        return text
    }

    func cancelCurrentWork() async {
        lock.withLock { cancelCount += 1 }
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

/// In-memory pasteboard double for PasteService/ClipboardRestoreService tests
/// (spec §12: never touch the real clipboard). `simulateExternalWrite`
/// mimics another app changing the clipboard mid-sequence.
@MainActor
final class MockPasteboard: Pasteboarding {
    private(set) var changeCount = 0
    /// nil models an empty or non-text pasteboard.
    private(set) var text: String?
    private(set) var setStringCalls: [String] = []

    init(initialText: String? = nil) {
        text = initialText
    }

    func string() -> String? { text }

    @discardableResult
    func setString(_ newText: String) -> Int {
        setStringCalls.append(newText)
        text = newText
        changeCount += 1
        return changeCount
    }

    /// Another app writes to the clipboard (bumps changeCount past ours).
    func simulateExternalWrite(_ newText: String?) {
        text = newText
        changeCount += 1
    }
}

/// Keyboard poster double: scriptable success plus an `onPost` hook so tests
/// can assert pasteboard state at the moment Cmd-V is posted (ordering).
@MainActor
final class MockKeyboardPoster: KeyboardPosting {
    var succeed = true
    var onPost: (() -> Void)?
    private(set) var postCount = 0

    func postCommandV() -> Bool {
        postCount += 1
        onPost?()
        return succeed
    }
}

/// Clock double: `sleep` suspends until the test explicitly fires or cancels it.
final class MockDictationClock: DictationClock, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [CheckedContinuation<Void, Error>] = []
    private(set) var sleepCount = 0
    private(set) var requestedDurations: [TimeInterval] = []

    func sleep(for duration: TimeInterval) async throws {
        lock.withLock {
            sleepCount += 1
            requestedDurations.append(duration)
        }
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
