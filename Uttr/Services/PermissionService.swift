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
        let canTap = CGEvent(
            keyboardEventSource: nil,
            virtualKey: 0,
            keyDown: true
        ) != nil
        return canTap ? .granted : .notGranted
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
