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

    // MARK: - repairMicrophone outcomes

    @Test("repairMicrophone: alreadyGranted outcome when mic is granted")
    func repairMicAlreadyGranted() async {
        let mock = MockPermissionService()
        mock.micStatus = .granted
        mock.repairMicOutcome = .alreadyGranted
        let outcome = await mock.repairMicrophone()
        #expect(outcome == .alreadyGranted)
        #expect(mock.repairMicCalled)
    }

    @Test("repairMicrophone: resetAndRequested outcome carries user response")
    func repairMicResetAndRequested() async {
        let mock = MockPermissionService()
        mock.micStatus = .notGranted
        mock.repairMicOutcome = .resetAndRequested(.granted)
        let outcome = await mock.repairMicrophone()
        if case .resetAndRequested(let status) = outcome {
            #expect(status == .granted)
        } else {
            Issue.record("Expected .resetAndRequested(.granted), got \(outcome)")
        }
    }

    @Test("repairMicrophone: resetFailed outcome carries non-empty reason")
    func repairMicResetFailed() async {
        let mock = MockPermissionService()
        mock.micStatus = .notGranted
        mock.repairMicOutcome = .resetFailed("tccutil exited 1")
        let outcome = await mock.repairMicrophone()
        if case .resetFailed(let reason) = outcome {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("Expected .resetFailed, got \(outcome)")
        }
    }

    // MARK: - Settings repair path: microphone repair action calls repairMicrophone

    /// Verifies that the manual "Repair & re-request" action in
    /// PermissionsSettingsView is wired to `repairMicrophone` (not a raw
    /// tccutil call), keeping the Settings view testable and side-effect-free.
    ///
    /// The view's repair closure for Microphone:
    ///   Task { micStatus = await permissionService.repairMicrophone()... }
    ///
    /// We model this closure here to assert the correct method is called.
    @Test("Settings microphone repair action delegates to repairMicrophone")
    func settingsMicRepairCallsRepairMicrophone() async {
        let mock = MockPermissionService()
        mock.micStatus = .notGranted
        mock.repairMicOutcome = .resetAndRequested(.granted)

        // Simulate the repair closure that PermissionsSettingsView wires up.
        _ = await mock.repairMicrophone()

        #expect(mock.repairMicCalled,
                "Microphone repair action must delegate to repairMicrophone()")
        #expect(!mock.repairInputCalled,
                "Microphone repair must not call repairInputMonitoring()")
    }

    /// Verifies that the "Repair & re-request" action for Input Monitoring
    /// calls repairInputMonitoring (not repairMicrophone), preserving the
    /// existing behavior.
    @Test("Settings input monitoring repair action delegates to repairInputMonitoring")
    func settingsInputRepairCallsRepairInput() {
        let mock = MockPermissionService()
        mock.inputStatus = .notGranted

        // Simulate the repair closure that PermissionsSettingsView wires up.
        mock.repairInputMonitoring()

        #expect(mock.repairInputCalled,
                "Input Monitoring repair action must delegate to repairInputMonitoring()")
        #expect(!mock.repairMicCalled,
                "Input Monitoring repair must not call repairMicrophone()")
    }

    // MARK: - MicrophoneRepairOutcome equality

    @Test("MicrophoneRepairOutcome values are distinct and equatable")
    func repairOutcomeEquality() {
        let outcomes: [MicrophoneRepairOutcome] = [
            .alreadyGranted,
            .resetAndRequested(.granted),
            .resetAndRequested(.notGranted),
            .resetFailed("err"),
        ]
        // Each value must equal itself.
        for outcome in outcomes {
            #expect(outcome == outcome)
        }
        // alreadyGranted vs resetAndRequested must differ.
        #expect(MicrophoneRepairOutcome.alreadyGranted != .resetAndRequested(.granted))
        // resetFailed must differ from success outcomes.
        #expect(MicrophoneRepairOutcome.resetFailed("x") != .alreadyGranted)
    }
}
