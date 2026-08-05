import Foundation
import OSLog
#if canImport(WhisperKit)
import WhisperKit
#endif

/// Thin abstraction over the WhisperKit package so unit tests never load a
/// real model. The production conformance is `WhisperKitClient` below.
protocol WhisperTranscribing: Sendable {
    /// Loads (downloading if needed) the named model. Idempotent.
    func loadModel(_ model: String) async throws
    /// Transcribes mono 16 kHz Float32 samples fully in memory.
    func transcribe(samples: [Float]) async throws -> String
}

/// `TranscriptionEngine` conformance backed by WhisperKit v1.0.0 (ADR-004).
/// Model naming: settings store short IDs ("small.en"); WhisperKit repo model
/// folders use the "openai_whisper-" prefix.
final class WhisperKitEngine: TranscriptionEngine {
    let id: TranscriptionEngineID = .whisperKit

    private let client: WhisperTranscribing
    private let model: String
    private let logger = Logger(subsystem: "com.uttr.app", category: "whisperkit")

    /// - Parameters:
    ///   - model: short model ID from settings, e.g. "small.en".
    ///   - client: injectable for tests; defaults to the real WhisperKit client.
    init(model: String, client: WhisperTranscribing? = nil) {
        self.model = model
        self.client = client ?? WhisperKitClient()
    }

    static func repoModelName(for shortID: String) -> String {
        "openai_whisper-\(shortID)"
    }

    func prepare() async throws {
        let start = Date()
        try await client.loadModel(Self.repoModelName(for: model))
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        logger.info("WhisperKit model prepared in \(ms, privacy: .public) ms")
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        let start = Date()
        do {
            let text = try await client.transcribe(samples: audio.samples)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            logger.info("Transcribed \(String(format: "%.1f", audio.duration), privacy: .public)s in \(ms, privacy: .public) ms")
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("Transcription failed: \(error.localizedDescription, privacy: .public)")
            throw UttrError.transcriptionFailed(underlying: error)
        }
    }

    func cancelCurrentWork() async {
        // WhisperKit v1.0.0 has no public cancellation for an in-flight
        // transcribe call; short dictation windows make this acceptable for M3.
        // Task-level cancellation is handled by the coordinator.
    }
}

/// Production adapter around the WhisperKit package.
/// Not exercised by unit tests (requires model download); validated manually
/// per the M3 Validator Packet.
///
/// The `canImport` guard exists because wiring the SPM dependency requires
/// Xcode 16.3+ (the project's native format); on older toolchains the app
/// still builds and reports `engineNotReady` instead of transcribing.
/// Tracked in docs/DECISIONS.md (ADR-007).
#if canImport(WhisperKit)
/// `@unchecked Sendable`: WhisperKit's class is not Sendable; access to the
/// stored instance is serialized through the synchronous locked accessors
/// below, and callers (TranscriptionCoordinator) never run loadModel and
/// transcribe concurrently for the same dictation.
final class WhisperKitClient: WhisperTranscribing, @unchecked Sendable {
    private let lock = NSLock()
    private var whisperKit: WhisperKit?
    private var loadedModel: String?

    // Synchronous accessors keep NSLock usage out of async contexts
    // (NSLock.lock/unlock are annotated noasync in Swift 6).
    private func currentInstance() -> WhisperKit? {
        lock.lock()
        defer { lock.unlock() }
        return whisperKit
    }

    private func isLoaded(_ model: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedModel == model && whisperKit != nil
    }

    private func store(_ instance: WhisperKit, model: String) {
        lock.lock()
        defer { lock.unlock() }
        whisperKit = instance
        loadedModel = model
    }

    func loadModel(_ model: String) async throws {
        if isLoaded(model) { return }

        // Downloads into WhisperKit's application-support location on first
        // use; never into the app bundle. No audio involved.
        let config = WhisperKitConfig(model: model)
        let instance = try await WhisperKit(config)
        store(instance, model: model)
    }

    func transcribe(samples: [Float]) async throws -> String {
        guard let instance = currentInstance() else { throw UttrError.engineNotReady }

        let results = await instance.transcribe(audioArrays: [samples])
        guard let first = results.first, let transcription = first else {
            return ""
        }
        return transcription.map(\.text).joined(separator: " ")
    }
}
#else
/// Placeholder used only when the WhisperKit package is not yet wired into
/// the project (pre-Xcode-16.3 toolchain). Always reports not ready.
final class WhisperKitClient: WhisperTranscribing, Sendable {
    func loadModel(_ model: String) async throws {
        throw UttrError.engineNotReady
    }

    func transcribe(samples: [Float]) async throws -> String {
        throw UttrError.engineNotReady
    }
}
#endif
