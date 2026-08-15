import Foundation
import OSLog

// MARK: - Storage abstraction

/// Minimal key-value storage interface so tests can inject an in-memory store
/// instead of `UserDefaults.standard`.
protocol BuildVersionStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

extension UserDefaults: BuildVersionStorage {
    func set(_ value: String?, forKey key: String) {
        if let value {
            set(value as Any, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}

// MARK: - Advisor outcome

/// The decision the advisor reaches for a given launch.
enum UpdateRepairDecision: Equatable, Sendable {
    /// First install or unknown baseline — do not reset anything.
    case firstInstall
    /// Build did not change since last launch — no action needed.
    case buildUnchanged
    /// Microphone is already granted — no reset needed.
    case microphoneAlreadyGranted
    /// Build changed and microphone is not granted — repair was attempted.
    case repairAttempted(MicrophoneRepairOutcome)
}

// MARK: - Advisor

/// Decides whether to repair microphone permission after a Sparkle (or any
/// other) update and drives the repair. Extracted from `AppEnvironment` so it
/// can be unit-tested without instantiating the full environment singleton.
///
/// Retry policy (documented here so tests can assert against it):
/// - First install (no previous build in storage): **no reset**. The TCC record
///   is fresh; resetting it at first launch would surprise the user.
/// - Same build as last launch: **no reset**. Nothing changed, no regression.
/// - Microphone already granted: **no reset**. Never touch a working grant.
/// - New build + microphone not granted: **repair attempted once** per build.
///   The build marker is written only after repair completes so a transient
///   failure (tccutil crash, non-zero exit) leaves the marker at the previous
///   build and makes this build eligible for another attempt on the next
///   launch. A deliberate user denial persists in TCC and will show
///   `.notGranted` again; the retry is limited to once per build-version to
///   avoid an intrusive prompt loop on every launch.
@MainActor
final class UpdatePermissionAdvisor {
    private let storage: BuildVersionStorage
    private let permissionService: PermissionChecking
    private let currentBuild: String
    private let logger = Logger(subsystem: "com.uttr.app", category: "update-advisor")

    static let buildVersionKey = "lastKnownBuildVersion"

    init(
        storage: BuildVersionStorage,
        permissionService: PermissionChecking,
        currentBuild: String
    ) {
        self.storage = storage
        self.permissionService = permissionService
        self.currentBuild = currentBuild
    }

    /// Evaluates whether microphone repair is warranted and performs it.
    /// Returns the decision reached so callers and tests can inspect it.
    @discardableResult
    func evaluateAndRepairIfNeeded() async -> UpdateRepairDecision {
        let previous = storage.string(forKey: Self.buildVersionKey) ?? ""

        // First install: no previous build stored.
        guard !previous.isEmpty else {
            logger.info("First install (build \(self.currentBuild, privacy: .public)) — skipping TCC repair")
            storage.set(currentBuild, forKey: Self.buildVersionKey)
            return .firstInstall
        }

        // Same build: nothing changed.
        guard currentBuild != previous else {
            return .buildUnchanged
        }

        // Microphone already granted: never reset a working permission.
        guard permissionService.microphoneStatus() == .notGranted else {
            logger.info("""
                Build changed (\(previous, privacy: .public) → \(self.currentBuild, privacy: .public)); \
                microphone already granted — no repair needed
                """)
            storage.set(currentBuild, forKey: Self.buildVersionKey)
            return .microphoneAlreadyGranted
        }

        // New build with missing microphone: attempt repair.
        logger.info("""
            Build changed (\(previous, privacy: .public) → \(self.currentBuild, privacy: .public)); \
            resetting stale microphone TCC record
            """)
        let outcome = await permissionService.repairMicrophone()

        // Write the new build marker ONLY after repair completes so that a
        // transient failure leaves this build eligible for retry on the next
        // launch (PR-43 review issue #3).
        switch outcome {
        case .alreadyGranted, .resetAndRequested:
            storage.set(currentBuild, forKey: Self.buildVersionKey)
            logger.info("Microphone repair outcome: \(String(describing: outcome), privacy: .public)")
        case .resetFailed(let reason):
            // Do NOT advance the marker: the next launch will try again.
            logger.error("Microphone repair failed: \(reason, privacy: .public) — will retry on next launch")
        }

        return .repairAttempted(outcome)
    }
}
