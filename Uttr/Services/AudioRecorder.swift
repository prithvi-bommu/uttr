import AVFoundation
import Accelerate
import Foundation
import OSLog

/// Abstraction over microphone capture so the dictation flow is fully testable
/// without a real microphone.
protocol AudioRecording: Sendable {
    /// Begins capture. Throws `UttrError.audioCaptureFailed` if the engine
    /// cannot start (missing permission surfaces here as well).
    func startRecording() async throws
    /// Ends capture and returns everything captured since start, normalized
    /// to mono Float32 at 16 kHz. Never writes to disk.
    func stopRecording() async -> CapturedAudio
    /// Discards any in-flight capture without producing audio.
    func cancelRecording() async
    /// Instantaneous input level (RMS, 0...~1) of the most recent audio
    /// buffer. 0 when not recording. Drives the recording indicator waveform.
    func currentAudioLevel() async -> Float
}

extension AudioRecording {
    func currentAudioLevel() async -> Float { 0 }
}

/// Validation policy from spec §8, refined for accuracy:
/// - Reject only genuinely-too-short captures (accidental key taps) below
///   `minimumDuration`; deliberate short words are kept and padded (below).
/// - Use RMS energy rather than peak amplitude to decide "no usable audio",
///   so quiet-but-real speech is no longer discarded on a single loud click.
/// - Cap at 120 s (enforced by the controller's timer; validated defensively).
/// Usable-but-short clips are zero-padded up to `minimumDecodeWindow` by
/// `rightPadded(_:)` so the decoder always sees a full analysis window
/// instead of dropping or garbling the dictation.
enum AudioPolicy {
    /// Below this we assume an accidental tap, not intentional dictation.
    static let minimumDuration: TimeInterval = 0.15
    static let maximumDuration: TimeInterval = 120
    /// Clips shorter than this (seconds) are right-padded with silence before
    /// decoding so short dictations aren't lost.
    static let minimumDecodeWindow: TimeInterval = 1.0
    /// RMS energy below this is treated as silence/no usable audio. RMS tracks
    /// perceived loudness far better than peak amplitude, so a brief transient
    /// no longer rescues an otherwise-silent buffer and quiet speech is kept.
    static let silenceRMSThreshold: Float = 0.001

    enum Verdict: Equatable {
        case usable
        case tooShort
        case noUsableAudio
    }

    static func evaluate(_ audio: CapturedAudio) -> Verdict {
        if audio.duration < minimumDuration { return .tooShort }
        if rootMeanSquare(audio.samples) < silenceRMSThreshold { return .noUsableAudio }
        return .usable
    }

    /// Root-mean-square energy of the samples, computed with vDSP.
    static func rootMeanSquare(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }

    /// Returns `audio` right-padded with trailing silence up to
    /// `minimumDecodeWindow`. Longer clips are returned unchanged.
    static func rightPadded(_ audio: CapturedAudio) -> CapturedAudio {
        guard audio.sampleRate > 0 else { return audio }
        let minimumSamples = Int(minimumDecodeWindow * audio.sampleRate)
        guard audio.samples.count < minimumSamples else { return audio }
        var padded = audio.samples
        padded.append(contentsOf:
            [Float](repeating: 0, count: minimumSamples - audio.samples.count))
        return CapturedAudio(samples: padded, sampleRate: audio.sampleRate)
    }
}

/// Lock-protected sample accumulator shared between the audio tap callback
/// (real-time thread) and the recorder actor. Conversion to 16 kHz mono
/// Float32 happens synchronously inside the tap so no non-Sendable AVFoundation
/// object ever crosses a concurrency boundary.
private final class CaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private var samples: [Float] = []
    private var latestLevel: Float = 0
    private let logger = Logger(subsystem: "com.uttr.app", category: "audio")

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat) {
        self.converter = converter
        self.targetFormat = targetFormat
        samples.reserveCapacity(Int(targetFormat.sampleRate * 30))
    }

    /// Called on the audio render thread by the input tap.
    func consume(_ buffer: AVAudioPCMBuffer) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 16)
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: out, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if let conversionError {
            logger.error("Buffer conversion failed: \(conversionError.localizedDescription, privacy: .public)")
            return
        }
        guard let channel = out.floatChannelData?[0] else { return }
        // Cheap per-buffer level for the recording indicator: one vDSP call,
        // no allocation — safe on the render thread.
        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(out.frameLength))
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        latestLevel = rms
        lock.unlock()
    }

    func currentLevel() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return latestLevel
    }

    func drain() -> [Float] {
        lock.lock()
        defer {
            samples = []
            lock.unlock()
        }
        return samples
    }
}

/// AVAudioEngine-backed recorder. Installs an input-node tap on start, buffers
/// converted samples in memory, and tears the tap down on stop/cancel.
/// All work happens off the main actor.
actor AVAudioEngineRecorder: AudioRecording {
    private let logger = Logger(subsystem: "com.uttr.app", category: "audio")

    private var engine: AVAudioEngine?
    private var captureState: CaptureState?

    private static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: CapturedAudio.requiredSampleRate,
        channels: 1,
        interleaved: false
    )!

    func startRecording() async throws {
        guard engine == nil else { return } // already recording; controller prevents this

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let nativeFormat = input.outputFormat(forBus: 0)

        guard nativeFormat.sampleRate > 0, nativeFormat.channelCount > 0 else {
            throw UttrError.audioCaptureFailed(
                underlying: NSError(
                    domain: "com.uttr.app.audio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No usable audio input device"]))
        }

        guard let converter = AVAudioConverter(from: nativeFormat, to: Self.targetFormat) else {
            throw UttrError.audioCaptureFailed(
                underlying: NSError(
                    domain: "com.uttr.app.audio", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Cannot convert input format"]))
        }

        let state = CaptureState(converter: converter, targetFormat: Self.targetFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
            state.consume(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw UttrError.audioCaptureFailed(underlying: error)
        }

        self.engine = engine
        self.captureState = state
        logger.info("Recording started (native \(nativeFormat.sampleRate, privacy: .public) Hz)")
    }

    func stopRecording() async -> CapturedAudio {
        let samples = tearDown()
        let audio = CapturedAudio(samples: samples, sampleRate: CapturedAudio.requiredSampleRate)
        logger.info("Recording stopped: \(String(format: "%.2f", audio.duration), privacy: .public)s captured")
        return audio
    }

    func cancelRecording() async {
        _ = tearDown()
        logger.info("Recording cancelled")
    }

    func currentAudioLevel() async -> Float {
        captureState?.currentLevel() ?? 0
    }

    // MARK: - Private

    private func tearDown() -> [Float] {
        guard let engine else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let samples = captureState?.drain() ?? []
        self.engine = nil
        self.captureState = nil
        return samples
    }
}
