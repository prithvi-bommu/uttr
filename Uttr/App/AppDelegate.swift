import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
    }

    /// Routes RevenueCat redemption callbacks to the payment gateway. Uttr's
    /// root scene is a `MenuBarExtra` and the app is `LSUIElement`, so
    /// SwiftUI's `.onOpenURL` is not a reliable delivery point — this is.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                await AppEnvironment.shared.paymentGateway.handleCallbackURL(url)
            }
        }
    }
}
