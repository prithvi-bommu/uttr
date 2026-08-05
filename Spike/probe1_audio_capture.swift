// Spike Probe 1: Microphone authorization + AVAudioEngine in-memory capture.
// Establishes: (a) AVCaptureDevice authorization API works from a CLI process,
// (b) AVAudioEngine input-node tap delivers PCM buffers entirely in memory,
// (c) the native input format, and conversion feasibility to mono 16 kHz Int16.
// Run: swiftc -o /tmp/probe1 probe1_audio_capture.swift && /tmp/probe1 [seconds]
// NOTE: actual capture requires the hosting terminal to have Microphone permission.

import AVFoundation
import Foundation

let seconds = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 3.0 : 3.0

// (a) Authorization status — non-prompting read, then request if undetermined.
let status = AVCaptureDevice.authorizationStatus(for: .audio)
print("mic authorizationStatus: \(status.rawValue) (0=notDetermined 1=restricted 2=denied 3=authorized)")

func capture() {
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let nativeFormat = input.outputFormat(forBus: 0)
    print("native input format: \(nativeFormat)")

    // Accumulate samples purely in memory — no file URL anywhere.
    final class Accumulator: @unchecked Sendable {
        var frames: AVAudioFrameCount = 0
        var peak: Float = 0
        let lock = NSLock()
    }
    let acc = Accumulator()

    input.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { buffer, _ in
        acc.lock.lock()
        acc.frames += buffer.frameLength
        if let ch = buffer.floatChannelData?[0] {
            for i in 0..<Int(buffer.frameLength) {
                acc.peak = max(acc.peak, abs(ch[i]))
            }
        }
        acc.lock.unlock()
    }

    do {
        try engine.start()
        print("engine started, capturing \(seconds)s in memory…")
        Thread.sleep(forTimeInterval: seconds)
        input.removeTap(onBus: 0)
        engine.stop()
        acc.lock.lock()
        let dur = Double(acc.frames) / nativeFormat.sampleRate
        print("captured frames: \(acc.frames) (\(String(format: "%.2f", dur))s), peak amplitude: \(acc.peak)")
        acc.lock.unlock()

        // (c) Prove AVAudioConverter path to mono 16 kHz Int16 exists.
        let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
        let converter = AVAudioConverter(from: nativeFormat, to: target)
        print("AVAudioConverter native→16kHz-mono-Int16: \(converter == nil ? "UNAVAILABLE" : "available")")
    } catch {
        print("engine.start FAILED: \(error)")
    }
}

if status == .authorized {
    capture()
} else if status == .notDetermined {
    let sem = DispatchSemaphore(value: 0)
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        print("requestAccess granted: \(granted)")
        if granted { capture() }
        sem.signal()
    }
    sem.wait()
} else {
    print("mic access denied/restricted — grant to the terminal app in System Settings → Privacy → Microphone")
}
