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
        .unknown
    }

    func inputMonitoringStatus() -> PermissionStatus {
        .unknown
    }

    func accessibilityStatus() -> PermissionStatus {
        .unknown
    }

    func requestMicrophone() async -> PermissionStatus {
        .unknown
    }

    func openInputMonitoringSettings() {
    }

    func openAccessibilitySettings() {
    }

    func openMicrophoneSettings() {
    }
}
