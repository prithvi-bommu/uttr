// Spike Probe 5: WhisperKit v1.0.0 in-memory transcription API.
// Establishes: (a) package resolves at v1.0.0 (commit 25c62997041c134b03ca82731ce2f6fd2cae1eb9),
// (b) the API accepts in-memory Float32 16 kHz mono samples with NO file URL,
// (c) model download goes to app-support/cache, not the bundle.
//
// API surface verified by source inspection of the v1.0.0 tag
// (Sources/WhisperKit/Core/WhisperKit.swift):
//   open func transcribe(audioArrays: [[Float]], decodeOptions:..., callback:...)
//       async -> [[TranscriptionResult]?]
//   WhisperKitConfig(model: String?, downloadBase:..., modelFolder:..., ...)
//
// Build (requires working Xcode toolchain — CLT on this Mac is broken, see ADR-002):
//   swift build   (from a package directory depending on WhisperKit v1.0.0)
// Run: downloads the tiny.en model on first use (~75 MB), transcribes 1s of silence.

import Foundation
#if canImport(WhisperKit)
import WhisperKit

@main
struct Probe5 {
    static func main() async {
        do {
            // Model resolves/downloads into WhisperKit's support directory, never the bundle.
            let config = WhisperKitConfig(model: "openai_whisper-tiny.en")
            let whisperKit = try await WhisperKit(config)
            print("WhisperKit loaded, modelFolder: \(whisperKit.modelFolder?.path ?? "nil")")

            // In-memory audio: 1 second of silence, 16 kHz mono Float32. No file URL.
            let silence = [Float](repeating: 0, count: 16_000)
            let results = await whisperKit.transcribe(audioArrays: [silence])
            let text = results.first??.map(\.text).joined() ?? ""
            print("transcript of silence: \"\(text)\" (expected: empty or noise token)")
        } catch {
            print("probe failed: \(error)")
        }
    }
}
#else
@main
struct Probe5 {
    static func main() {
        print("WhisperKit not resolvable in this build context — run via SPM package with the dependency declared")
    }
}
#endif
