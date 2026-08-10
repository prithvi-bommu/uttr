import AppKit

/// Brings this accessory app's windows to the front reliably.
///
/// Uttr has no Dock icon (menu-bar only), and macOS's cooperative activation
/// (macOS 14+) routinely declines `NSApplication.activate()` requests from
/// accessory apps — windows then open BEHIND the frontmost app and users have
/// to dig for them. This helper pairs a forceful activation with an explicit
/// order-front of the specific window, retrying briefly because SwiftUI
/// creates scene windows asynchronously after `openWindow`/`SettingsLink`.
@MainActor
enum WindowFocus {
    /// Substrings that identify the SwiftUI Settings scene window across
    /// OS versions (identifier is private API shaped, so match loosely).
    private static let settingsMarkers = ["settings", "preferences"]

    /// Focuses the window whose identifier contains `sceneID`
    /// (e.g. "onboarding", "diagnostics" — SwiftUI embeds the scene id).
    static func focusWindow(sceneID: String) {
        focus { window in
            Self.identifierMatches(window.identifier?.rawValue, marker: sceneID)
        }
    }

    /// Focuses the SwiftUI Settings window.
    static func focusSettingsWindow() {
        focus { window in
            settingsMarkers.contains {
                Self.identifierMatches(window.identifier?.rawValue, marker: $0)
            }
        }
    }

    /// Pure matcher, unit-testable: case-insensitive containment.
    static func identifierMatches(_ identifier: String?, marker: String) -> Bool {
        guard let identifier else { return false }
        return identifier.lowercased().contains(marker.lowercased())
    }

    // MARK: - Private

    private static func focus(where predicate: @escaping (NSWindow) -> Bool) {
        activateApp()
        attemptOrderFront(retries: 20, predicate: predicate)
    }

    private static func activateApp() {
        // The non-deprecated activate() is exactly the call cooperative
        // activation ignores for accessory apps; ignoringOtherApps is
        // deprecated on macOS 14+ but remains the only reliable way to
        // take focus from a status-item context.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// SwiftUI materializes scene windows a runloop turn (or several) after
    /// the open call, so poll briefly. 20 × 50 ms = 1 s worst case; stops at
    /// first match. The indicator pill panel can never match: it has no
    /// identifier and ignores mouse events anyway.
    private static func attemptOrderFront(
        retries: Int, predicate: @escaping (NSWindow) -> Bool
    ) {
        if let window = NSApp.windows.first(where: predicate) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            attemptOrderFront(retries: retries - 1, predicate: predicate)
        }
    }
}
