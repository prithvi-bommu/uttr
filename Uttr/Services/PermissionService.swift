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
