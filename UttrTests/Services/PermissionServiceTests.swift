import Testing
@testable import Uttr

@Suite("PermissionService")
struct PermissionServiceTests {

    @Test("mock permission service returns configured statuses")
    func mockStatuses() {
        let mock = MockPermissionService()
        mock.micStatus = .granted
        mock.inputStatus = .notGranted
        mock.accessStatus = .unknown

        #expect(mock.microphoneStatus() == .granted)
        #expect(mock.inputMonitoringStatus() == .notGranted)
        #expect(mock.accessibilityStatus() == .unknown)
    }

    @Test("mock permission service tracks open calls")
    func mockOpenCalls() {
        let mock = MockPermissionService()
        mock.openMicrophoneSettings()
        mock.openInputMonitoringSettings()
        mock.openAccessibilitySettings()

        #expect(mock.openMicCalled)
        #expect(mock.openInputCalled)
        #expect(mock.openAccessCalled)
    }

    @Test("mock permission service request microphone")
    func mockRequestMic() async {
        let mock = MockPermissionService()
        mock.requestMicResult = .granted
        let result = await mock.requestMicrophone()
        #expect(result == .granted)
    }

    @Test("permission blocker maps correctly")
    func blockerMapping() {
        #expect(PermissionBlocker.microphone.statusText.contains("Microphone"))
        #expect(PermissionBlocker.inputMonitoring.statusText.contains("Input Monitoring"))
        #expect(PermissionBlocker.accessibility.statusText.contains("Accessibility"))
    }

    @Test("all three permission statuses are distinct")
    func statusEquality() {
        #expect(PermissionStatus.granted != .notGranted)
        #expect(PermissionStatus.notGranted != .unknown)
        #expect(PermissionStatus.granted != .unknown)
    }
}
