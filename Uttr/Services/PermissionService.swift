import AVFoundation
import AppKit
import ApplicationServices
import Foundation

enum PermissionStatus: Equatable, Sendable {
    case granted
    case notGranted
    case unknown
}

protocol PermissionChecking: Sendable {
    func microphoneStatus() -> PermissionStatus
    func inputMonitoringStatus() -> PermissionStatus
    func accessibilityStatus() -> PermissionStatus
    func requestMicrophone() async -> PermissionStatus
    /// Triggers the system Input Monitoring prompt/registration.
    /// - Returns: true if access is already granted; false when the request
    ///   was filed (macOS applies the grant only after an app relaunch).
    @discardableResult
    func requestInputMonitoring() -> Bool
    /// Triggers the system Accessibility prompt/registration.
    /// - Returns: true if the process is already trusted; false when the
    ///   prompt was shown (grant requires a relaunch to take effect).
    @discardableResult
    func requestAccessibility() -> Bool
    /// Clears Uttr's own stale Microphone record and re-requests.
    /// After a signing identity change macOS may leave a stale "denied"
    /// record that prevents the system prompt from reappearing.
    func repairMicrophone() async -> PermissionStatus
    /// Clears Uttr's own stale Input Monitoring record and re-requests.
    /// Fixes the "pane opens but Uttr isn't listed" dead end that stale
    /// records from earlier (differently-signed) builds cause: macOS refuses
    /// to re-prompt while a stale decision exists. Never called when the
    /// permission is already granted.
    func repairInputMonitoring()
    /// Reveals Uttr.app in Finder so the user can drag it straight into an
    /// open privacy pane. macOS 15 does not auto-register ad-hoc-signed apps
    /// in the Input Monitoring pane (ADR-009), so pre-M7 builds need this
    /// assisted manual add.
    func revealAppForManualAdd()
    func openInputMonitoringSettings()
    func openAccessibilitySettings()
    func openMicrophoneSettings()
}

struct RealPermissionService: PermissionChecking {
    func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .notGranted
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }

    func inputMonitoringStatus() -> PermissionStatus {
        // CGPreflightListenEventAccess is the authoritative check. The old
        // CGEvent-creation probe never required Input Monitoring and always
        // reported granted, masking real tap failures.
        CGPreflightListenEventAccess() ? .granted : .notGranted
    }

    func accessibilityStatus() -> PermissionStatus {
        AXIsProcessTrusted() ? .granted : .notGranted
    }

    func requestMicrophone() async -> PermissionStatus {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        return granted ? .granted : .notGranted
    }

    @discardableResult
    func requestInputMonitoring() -> Bool {
        // Registers Uttr in the Input Monitoring pane and shows the system
        // prompt when undetermined. Returns true only when already granted;
        // a fresh grant takes effect after relaunch (ADR-006).
        CGRequestListenEventAccess()
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        // Registers Uttr in the Accessibility pane and shows the system
        // prompt when not yet trusted. A fresh grant requires relaunch.
        // Literal key equals kAXTrustedCheckOptionPrompt ("AXTrustedCheckOptionPrompt",
        // AXUIElement.h); the SDK global var is not concurrency-safe under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func repairMicrophone() async -> PermissionStatus {
        guard microphoneStatus() != .granted else { return .granted }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Microphone", "com.uttr.app"]
        try? process.run()
        process.waitUntilExit()
        return await requestMicrophone()
    }

    func repairInputMonitoring() {
        // Guard: never touch a working grant.
        guard inputMonitoringStatus() != .granted else { return }
        // tccutil resets only Uttr's own records (bundle-id scoped, no sudo).
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ListenEvent", "com.uttr.app"]
        try? process.run()
        process.waitUntilExit()
        // With the stale record gone, the request shows the system prompt
        // again and auto-registers the row in the Input Monitoring pane.
        _ = CGRequestListenEventAccess()
    }

    func revealAppForManualAdd() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func openInputMonitoringSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    func openAccessibilitySettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openMicrophoneSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    private func openSystemSettings(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
