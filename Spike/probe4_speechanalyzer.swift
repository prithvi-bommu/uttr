// Spike Probe 4: SpeechAnalyzer / SpeechTranscriber availability.
// Establishes: (a) whether the installed SDK exposes the macOS 26 Speech APIs at
// compile time, (b) whether the running OS satisfies #available(macOS 26.0, *),
// (c) if available at runtime, whether the en-US transcriber module reports
// supported/installed status via the asset inventory.
// Run: swiftc -o /tmp/probe4 probe4_speechanalyzer.swift && /tmp/probe4

import Foundation
import Speech

print("ProcessInfo OS version: \(ProcessInfo.processInfo.operatingSystemVersionString)")

#if compiler(>=6.0)
print("compile-time: building in Swift 6 language mode")
#endif

if #available(macOS 26.0, *) {
    print("runtime: macOS 26+ — SpeechAnalyzer path AVAILABLE")
    Task {
        do {
            let locale = Locale(identifier: "en-US")
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            let supported = await SpeechTranscriber.supportedLocales
            let installed = await SpeechTranscriber.installedLocales
            print("supported locales: \(supported.map(\.identifier))")
            print("installed locales: \(installed.map(\.identifier))")
            if let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                print("asset download would be required (request: \(req))")
            } else {
                print("assets already installed for en-US")
            }
        } catch {
            print("SpeechTranscriber probe error: \(error)")
        }
        exit(0)
    }
    RunLoop.main.run()
} else {
    print("runtime: macOS < 26 — SpeechAnalyzer path UNAVAILABLE on this machine")
    print("=> M3 must ride on WhisperKit here; System Speech engine (M5) needs a macOS 26 validation Mac")
}
