import Foundation
import Testing
@testable import Uttr

@Suite("AudioPolicy")
struct AudioPolicyTests {

    private func audio(seconds: Double, amplitude: Float) -> CapturedAudio {
        CapturedAudio(
            samples: [Float](repeating: amplitude, count: Int(16_000 * seconds)),
            sampleRate: 16_000
        )
    }

    @Test("rejects recordings shorter than the accidental-tap floor")
    func rejectsTooShort() {
        #expect(AudioPolicy.evaluate(audio(seconds: 0.05, amplitude: 0.5)) == .tooShort)
        #expect(AudioPolicy.evaluate(audio(seconds: 0.14, amplitude: 0.5)) == .tooShort)
    }

    @Test("accepts deliberate short words above the floor")
    func acceptsShortWord() {
        // A ~200 ms word used to be rejected by the old 250 ms floor.
        #expect(AudioPolicy.evaluate(audio(seconds: 0.2, amplitude: 0.2)) == .usable)
    }

    @Test("rejects empty capture")
    func rejectsEmpty() {
        let empty = CapturedAudio(samples: [], sampleRate: 16_000)
        #expect(AudioPolicy.evaluate(empty) == .tooShort)
    }

    @Test("rejects silence as no usable audio")
    func rejectsSilence() {
        #expect(AudioPolicy.evaluate(audio(seconds: 2, amplitude: 0)) == .noUsableAudio)
        #expect(AudioPolicy.evaluate(audio(seconds: 2, amplitude: 0.0005)) == .noUsableAudio)
    }

    @Test("accepts normal speech-level audio")
    func acceptsUsable() {
        #expect(AudioPolicy.evaluate(audio(seconds: 0.3, amplitude: 0.2)) == .usable)
        #expect(AudioPolicy.evaluate(audio(seconds: 5, amplitude: 0.01)) == .usable)
    }

    @Test("RMS is computed from the samples")
    func rmsComputation() {
        // Constant-amplitude signal: RMS == amplitude.
        let samples = [Float](repeating: 0.5, count: 1000)
        #expect(abs(AudioPolicy.rootMeanSquare(samples) - 0.5) < 0.0001)
        #expect(AudioPolicy.rootMeanSquare([]) == 0)
    }

    @Test("a lone moderate click in silence is rejected")
    func rejectsIsolatedClick() {
        // Peak amplitude 0.1 is 100x the threshold, so the previous peak-based
        // check accepted this as usable audio. RMS over the 2 s buffer is only
        // ~0.00056, so it is now correctly treated as silence.
        var samples = [Float](repeating: 0, count: 32_000)
        samples[100] = 0.1
        let audio = CapturedAudio(samples: samples, sampleRate: 16_000)
        #expect(AudioPolicy.rootMeanSquare(samples) < AudioPolicy.silenceRMSThreshold)
        #expect(AudioPolicy.evaluate(audio) == .noUsableAudio)
    }

    @Test("right-pads short clips up to the minimum decode window")
    func rightPadsShortClips() {
        let short = CapturedAudio(
            samples: [Float](repeating: 0.3, count: 8_000), // 0.5 s
            sampleRate: 16_000)
        let padded = AudioPolicy.rightPadded(short)
        #expect(padded.samples.count == 16_000) // 1.0 s window
        #expect(padded.samples.prefix(8_000).allSatisfy { $0 == 0.3 })
        #expect(padded.samples.suffix(8_000).allSatisfy { $0 == 0 })
    }

    @Test("does not pad clips already at or above the window")
    func doesNotPadLongClips() {
        let long = CapturedAudio(
            samples: [Float](repeating: 0.3, count: 32_000), // 2 s
            sampleRate: 16_000)
        #expect(AudioPolicy.rightPadded(long).samples.count == 32_000)
    }

    @Test("duration derives from sample count and rate")
    func durationDerivation() {
        let audio = CapturedAudio(samples: [Float](repeating: 0.1, count: 8_000), sampleRate: 16_000)
        #expect(audio.duration == 0.5)
    }
}

@Suite("WhisperKitEngine")
struct WhisperKitEngineTests {

    @Test("maps short model IDs to WhisperKit repo names")
    func modelNameMapping() {
        #expect(WhisperKitEngine.repoModelName(for: "small.en") == "openai_whisper-small.en")
        #expect(WhisperKitEngine.repoModelName(for: "tiny.en") == "openai_whisper-tiny.en")
    }

    @Test("prepare loads the configured model")
    func prepareLoadsModel() async throws {
        let client = MockWhisperClient()
        let engine = WhisperKitEngine(model: "base.en", client: client)
        try await engine.prepare()
        #expect(client.loadedModels == ["openai_whisper-base.en"])
    }

    @Test("transcribe passes samples through and trims whitespace")
    func transcribePassesSamples() async throws {
        let client = MockWhisperClient()
        client.textToReturn = "  hello there \n"
        let engine = WhisperKitEngine(model: "small.en", client: client)
        let audio = CapturedAudio(samples: [0.1, 0.2, 0.3], sampleRate: 16_000)

        let text = try await engine.transcribe(audio)

        #expect(text == "hello there")
        #expect(client.receivedSamples.count == 1)
        #expect(client.receivedSamples[0] == [0.1, 0.2, 0.3])
    }

    @Test("transcription failure wraps in UttrError.transcriptionFailed")
    func transcribeFailureWraps() async {
        let client = MockWhisperClient()
        client.transcribeError = NSError(domain: "test", code: 9)
        let engine = WhisperKitEngine(model: "small.en", client: client)
        let audio = CapturedAudio(samples: [0.1], sampleRate: 16_000)

        await #expect(throws: UttrError.self) {
            _ = try await engine.transcribe(audio)
        }
    }
}
