import AVFoundation
import Foundation
import OSLog

#if compiler(>=6.2)
import Speech
#endif

protocol SystemSpeechTranscribing: Sendable {
    func prepare() async throws
    func transcribe(_ audio: CapturedAudio) async throws -> String
    func cancelCurrentWork() async
}

/// Apple on-device speech engine for macOS 26 and newer. The adapter keeps
/// all audio in memory and presents the same `TranscriptionEngine` contract as
/// WhisperKit, so automatic selection can switch engines without changing the
/// dictation pipeline.
final class SpeechAnalyzerEngine: TranscriptionEngine {
    let id: TranscriptionEngineID = .systemSpeech

    private let client: SystemSpeechTranscribing
    private let logger = Logger(subsystem: "com.uttr.app", category: "system-speech")

    init(client: SystemSpeechTranscribing? = nil) {
        self.client = client ?? RuntimeSystemSpeechClient.make()
    }

    func prepare() async throws {
        try await client.prepare()
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        do {
            return HallucinationFilter.clean(try await client.transcribe(audio))
        } catch {
            logger.error("System Speech transcription failed: \(error.localizedDescription, privacy: .public)")
            throw UttrError.transcriptionFailed(underlying: error)
        }
    }

    func cancelCurrentWork() async {
        await client.cancelCurrentWork()
    }
}

enum RuntimeSystemSpeechClient {
    static func make() -> SystemSpeechTranscribing {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return AppleSpeechAnalyzerClient()
        }
        #endif
        return UnavailableSystemSpeechClient()
    }

    static var isAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return SpeechTranscriber.isAvailable
        }
        #endif
        return false
    }
}

private struct UnavailableSystemSpeechClient: SystemSpeechTranscribing {
    func prepare() async throws { throw UttrError.engineNotReady }
    func transcribe(_ audio: CapturedAudio) async throws -> String {
        throw UttrError.engineNotReady
    }
    func cancelCurrentWork() async {}
}

#if compiler(>=6.2)
@available(macOS 26.0, *)
private actor AppleSpeechAnalyzerClient: SystemSpeechTranscribing {
    private let requestedLocale = Locale(identifier: "en-US")
    private var preparedLocale: Locale?
    private var currentAnalyzer: SpeechAnalyzer?

    func prepare() async throws {
        guard SpeechTranscriber.isAvailable else { throw UttrError.engineNotReady }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw NSError(
                domain: "com.uttr.app.system-speech",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "English System Speech transcription is unavailable."])
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        _ = try await AssetInventory.reserve(locale: locale)
        preparedLocale = locale
    }

    func transcribe(_ audio: CapturedAudio) async throws -> String {
        guard let locale = preparedLocale else { throw UttrError.engineNotReady }
        guard audio.sampleRate > 0, !audio.samples.isEmpty else { return "" }

        let format = try Self.audioFormat(sampleRate: audio.sampleRate)
        let buffer = try Self.audioBuffer(samples: audio.samples, format: format)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        currentAnalyzer = analyzer
        defer { currentAnalyzer = nil }

        try await analyzer.prepareToAnalyze(in: format)

        let resultTask = Task<String, Error> {
            var parts: [String] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            }
            return parts.joined(separator: " ")
        }

        let input = AsyncStream<AnalyzerInput> { continuation in
            continuation.yield(AnalyzerInput(buffer: buffer))
            continuation.finish()
        }

        do {
            _ = try await analyzer.analyzeSequence(input)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            return try await resultTask.value
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }

    func cancelCurrentWork() async {
        await currentAnalyzer?.cancelAndFinishNow()
    }

    private nonisolated static func audioFormat(sampleRate: Double) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false)
        else {
            throw NSError(
                domain: "com.uttr.app.system-speech", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create the speech audio format."])
        }
        return format
    }

    private nonisolated static func audioBuffer(
        samples: [Float], format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)),
            let destination = buffer.floatChannelData?[0]
        else {
            throw NSError(
                domain: "com.uttr.app.system-speech", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create the speech audio buffer."])
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            guard let sourceAddress = source.baseAddress else { return }
            destination.update(from: sourceAddress, count: source.count)
        }
        return buffer
    }
}
#endif
