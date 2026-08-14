import Foundation
import AppKit

// Official releases are Developer ID signed and notarized. Sparkle can retain
// the app's stable identity across updates; see ADR-011 for release safeguards.
@MainActor
protocol UpdaterServicing: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    func checkForUpdates()
}

#if canImport(Sparkle)
import Sparkle

@MainActor
@Observable
final class SparkleUpdaterService: UpdaterServicing {
    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        updaterController.updater.checkForUpdates()
    }
}
#else
@MainActor
@Observable
final class SparkleUpdaterService: UpdaterServicing {
    var automaticallyChecksForUpdates: Bool = false
    var canCheckForUpdates: Bool { false }
    var lastUpdateCheckDate: Date? { nil }
    func checkForUpdates() {}
}
#endif
