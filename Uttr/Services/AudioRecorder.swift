import AVFoundation
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
}

/// Validation policy from spec §8: reject dictations shorter than 250 ms or
/// containing no meaningful signal; cap at 120 s (enforced by the controller's
/// timer, validated again here defensively).
enum AudioPolicy {
    static let minimumDuration: TimeInterval = 0.25
    static let maximumDuration: TimeInterval = 120
    /// Peak amplitude below this is treated as silence/no usable audio.
    static let silencePeakThreshold: Float = 0.001

    enum Verdict: Equatable {
        case usable
        case tooShort
        case noUsableAudio
    }

    static func evaluate(_ audio: CapturedAudio) -> Verdict {
        if audio.duration < minimumDuration { return .tooShort }
        var peak: Float = 0
        for sample in audio.samples {
            peak = max(peak, abs(sample))
        }
        if peak < silencePeakThreshold { return .noUsableAudio }
        return .usable
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
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        lock.unlock()
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
