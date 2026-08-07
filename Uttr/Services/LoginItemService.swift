import Foundation
import OSLog
import ServiceManagement

/// Abstraction over the system login-item registration so views and tests
/// never touch `SMAppService` directly.
protocol LoginItemManaging: Sendable {
    /// True when the app is currently registered to start at login.
    var isEnabled: Bool { get }
    /// Registers or unregisters the app as a login item.
    /// Throws when the system refuses (e.g. app not in a stable location).
    func setEnabled(_ enabled: Bool) throws
}

/// Production implementation backed by `SMAppService.mainApp` (macOS 13+).
///
/// Notes:
/// - Registration sticks across launches; macOS keys it to the app's
///   location and identity, so moving or re-signing the app can require
///   re-registering (same cdhash caveat as the TCC grants, ADR-006/009).
/// - `.requiresApproval` means the user disabled it in System Settings →
///   General → Login Items; we surface that as "enabled request accepted"
///   (register does not throw) but `isEnabled` stays false until approved.
struct SMAppServiceLoginItem: LoginItemManaging {
    private static let logger = Logger(subsystem: "com.uttr.app", category: "loginitem")

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            Self.logger.info("Login item registered (status: \(String(describing: SMAppService.mainApp.status), privacy: .public))")
        } else {
            try SMAppService.mainApp.unregister()
            Self.logger.info("Login item unregistered")
        }
    }
}
