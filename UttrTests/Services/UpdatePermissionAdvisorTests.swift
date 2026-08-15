import Testing
@testable import Uttr

// MARK: - UpdatePermissionAdvisorTests
//
// These tests cover the update/permission-repair decision logic in isolation.
// No real tccutil is invoked; all I/O is injected via test doubles.
//
// Retry / idempotency policy under test (see UpdatePermissionAdvisor for the
// canonical description):
//   • First install (no previous build stored)  → no repair, marker set.
//   • Same build as last launch                 → no repair.
//   • Microphone already granted                → no repair, marker advanced.
//   • New build + mic not granted               → repair attempted once.
//   • Repair failure (tccutil error)            → marker NOT advanced (retry eligible).
//   • Repair success (any non-failure outcome)  → marker advanced.

@Suite("UpdatePermissionAdvisor")
@MainActor
struct UpdatePermissionAdvisorTests {

    // MARK: Helpers

    private struct AdvisorFixture {
        let advisor: UpdatePermissionAdvisor
        let permission: MockPermissionService
        let storage: MockBuildVersionStorage
    }

    private func makeAdvisor(
        previousBuild: String? = nil,
        currentBuild: String = "100",
        micStatus: PermissionStatus = .notGranted,
        repairOutcome: MicrophoneRepairOutcome = .resetAndRequested(.granted)
    ) -> AdvisorFixture {
        let storage = MockBuildVersionStorage()
        if let prev = previousBuild {
            storage.set(prev, forKey: UpdatePermissionAdvisor.buildVersionKey)
        }
        let permission = MockPermissionService()
        permission.micStatus = micStatus
        permission.repairMicOutcome = repairOutcome
        let advisor = UpdatePermissionAdvisor(
            storage: storage,
            permissionService: permission,
            currentBuild: currentBuild
        )
        return AdvisorFixture(advisor: advisor, permission: permission, storage: storage)
    }

    // MARK: - First install

    @Test("first install: no repair, build marker is set")
    func firstInstall() async {
        let fx = makeAdvisor(previousBuild: nil, currentBuild: "1")
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(decision == .firstInstall)
        #expect(!fx.permission.repairMicCalled, "tccutil must not be invoked on first install")
        #expect(fx.storage.string(forKey: UpdatePermissionAdvisor.buildVersionKey) == "1",
                "build marker must be stored after first install")
    }

    // MARK: - Build unchanged

    @Test("same build: no repair triggered")
    func buildUnchanged() async {
        let fx = makeAdvisor(previousBuild: "42", currentBuild: "42")
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(decision == .buildUnchanged)
        #expect(!fx.permission.repairMicCalled)
    }

    // MARK: - Microphone already granted

    @Test("new build but microphone already granted: no reset")
    func microphoneAlreadyGranted() async {
        let fx = makeAdvisor(
            previousBuild: "10",
            currentBuild: "11",
            micStatus: .granted
        )
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(decision == .microphoneAlreadyGranted)
        #expect(!fx.permission.repairMicCalled, "must never reset a working microphone grant")
        #expect(fx.storage.string(forKey: UpdatePermissionAdvisor.buildVersionKey) == "11",
                "build marker should advance even when no repair was needed")
    }

    // MARK: - Repair triggered

    @Test("new build + microphone not granted: repair is attempted")
    func repairTriggeredOnNewBuild() async {
        let fx = makeAdvisor(
            previousBuild: "20",
            currentBuild: "21",
            micStatus: .notGranted,
            repairOutcome: .resetAndRequested(.granted)
        )
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(fx.permission.repairMicCalled)
        if case .repairAttempted(.resetAndRequested(.granted)) = decision { } else {
            Issue.record("Expected repairAttempted(.resetAndRequested(.granted)), got \(decision)")
        }
    }

    @Test("successful repair advances the build marker")
    func successfulRepairAdvancesMarker() async {
        let fx = makeAdvisor(
            previousBuild: "30",
            currentBuild: "31",
            micStatus: .notGranted,
            repairOutcome: .resetAndRequested(.granted)
        )
        await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(fx.storage.string(forKey: UpdatePermissionAdvisor.buildVersionKey) == "31")
    }

    @Test("user denied after reset: build marker still advances (deliberate denial)")
    func userDenialAfterResetAdvancesMarker() async {
        // The user explicitly denied the system prompt. We should NOT loop on
        // every subsequent launch for the same build; the marker must advance.
        let fx = makeAdvisor(
            previousBuild: "40",
            currentBuild: "41",
            micStatus: .notGranted,
            repairOutcome: .resetAndRequested(.notGranted)
        )
        await fx.advisor.evaluateAndRepairIfNeeded()

        #expect(fx.storage.string(forKey: UpdatePermissionAdvisor.buildVersionKey) == "41",
                "marker must advance after deliberate user denial to prevent prompt loops")
    }

    // MARK: - Repair failure / retry eligibility

    @Test("tccutil failure: build marker is NOT advanced (retry eligible on next launch)")
    func failedRepairDoesNotAdvanceMarker() async {
        let fx = makeAdvisor(
            previousBuild: "50",
            currentBuild: "51",
            micStatus: .notGranted,
            repairOutcome: .resetFailed("tccutil exited 1")
        )
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()

        if case .repairAttempted(.resetFailed) = decision { } else {
            Issue.record("Expected repairAttempted(.resetFailed), got \(decision)")
        }
        #expect(fx.storage.string(forKey: UpdatePermissionAdvisor.buildVersionKey) == "50",
                "marker must stay at previous build so next launch retries")
    }

    @Test("tccutil failure is observable via MicrophoneRepairOutcome")
    func repairFailureOutcomeIsObservable() async {
        let fx = makeAdvisor(
            previousBuild: "60",
            currentBuild: "61",
            micStatus: .notGranted,
            repairOutcome: .resetFailed("tccutil launch failed: some error")
        )
        let decision = await fx.advisor.evaluateAndRepairIfNeeded()
        guard case .repairAttempted(let outcome) = decision else {
            Issue.record("Expected repairAttempted")
            return
        }
        guard case .resetFailed(let reason) = outcome else {
            Issue.record("Expected resetFailed outcome")
            return
        }
        #expect(!reason.isEmpty, "Failure reason must be non-empty so it can be logged")
    }

    // MARK: - Input Monitoring (existing behavior unchanged)

    @Test("input monitoring repair does not interfere with microphone advisor")
    func inputMonitoringRepairIsIndependent() async {
        let fx = makeAdvisor(
            previousBuild: "70",
            currentBuild: "70",  // same build → build-unchanged path
            micStatus: .notGranted
        )
        await fx.advisor.evaluateAndRepairIfNeeded()

        // repairInputMonitoring is driven separately (PermissionsSettingsView /
        // repairInputMonitoring on the service); the advisor must not touch it.
        #expect(!fx.permission.repairInputCalled)
    }
}
