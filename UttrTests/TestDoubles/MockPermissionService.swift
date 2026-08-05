import Foundation
@testable import Uttr

final class MockPermissionService: PermissionChecking, @unchecked Sendable {
    var micStatus: PermissionStatus = .granted
    var inputStatus: PermissionStatus = .granted
    var accessStatus: PermissionStatus = .granted
    var requestMicResult: PermissionStatus = .granted
    var openMicCalled = false
    var openInputCalled = false
    var openAccessCalled = false

    func microphoneStatus() -> PermissionStatus { micStatus }
    func inputMonitoringStatus() -> PermissionStatus { inputStatus }
    func accessibilityStatus() -> PermissionStatus { accessStatus }

    func requestMicrophone() async -> PermissionStatus {
        requestMicResult
    }

    func openInputMonitoringSettings() { openInputCalled = true }
    func openAccessibilitySettings() { openAccessCalled = true }
    func openMicrophoneSettings() { openMicCalled = true }
}
