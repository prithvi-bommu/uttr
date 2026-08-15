import Foundation
@testable import Uttr

final class MockPermissionService: PermissionChecking, @unchecked Sendable {
    var micStatus: PermissionStatus = .granted
    var inputStatus: PermissionStatus = .granted
    var accessStatus: PermissionStatus = .granted
    var requestMicResult: PermissionStatus = .granted
    var requestInputResult = false
    var requestAccessResult = false
    var openMicCalled = false
    var openInputCalled = false
    var openAccessCalled = false
    var requestInputCalled = false
    var requestAccessCalled = false

    func microphoneStatus() -> PermissionStatus { micStatus }
    func inputMonitoringStatus() -> PermissionStatus { inputStatus }
    func accessibilityStatus() -> PermissionStatus { accessStatus }

    func requestMicrophone() async -> PermissionStatus {
        requestMicResult
    }

    @discardableResult
    func requestInputMonitoring() -> Bool {
        requestInputCalled = true
        return requestInputResult
    }

    @discardableResult
    func requestAccessibility() -> Bool {
        requestAccessCalled = true
        return requestAccessResult
    }

    var repairMicCalled = false
    func repairMicrophone() async -> PermissionStatus {
        repairMicCalled = true
        return requestMicResult
    }

    var repairInputCalled = false
    func repairInputMonitoring() { repairInputCalled = true }

    var revealAppCalled = false
    func revealAppForManualAdd() { revealAppCalled = true }

    func openInputMonitoringSettings() { openInputCalled = true }
    func openAccessibilitySettings() { openAccessCalled = true }
    func openMicrophoneSettings() { openMicCalled = true }
}
