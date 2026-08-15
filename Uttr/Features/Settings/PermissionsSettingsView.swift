import Combine
import SwiftUI

struct PermissionsSettingsView: View {
    let permissionService: PermissionChecking

    @State private var micStatus: PermissionStatus = .unknown
    @State private var inputStatus: PermissionStatus = .unknown
    @State private var accessibilityStatus: PermissionStatus = .unknown

    var body: some View {
        Form {
            Section("Required Permissions") {
                permissionRow(
                    title: "Microphone",
                    description: "Required to capture your voice during dictation.",
                    status: micStatus,
                    actions: .init(
                        request: {
                            Task { @MainActor in
                                micStatus = await permissionService.requestMicrophone()
                            }
                        },
                        repair: {
                            Task { @MainActor in
                                micStatus = await permissionService.repairMicrophone()
                            }
                        },
                        openSettings: { permissionService.openMicrophoneSettings() }
                    )
                )

                permissionRow(
                    title: "Input Monitoring",
                    description: "Required to detect your global dictation shortcut.",
                    status: inputStatus,
                    actions: .init(
                        request: {
                            permissionService.requestInputMonitoring()
                            refreshStatus()
                        },
                        repair: {
                            permissionService.repairInputMonitoring()
                            refreshStatus()
                        },
                        openSettings: {
                            permissionService.openInputMonitoringSettings()
                            permissionService.revealAppForManualAdd()
                        }
                    )
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required to paste transcribed text into other applications.",
                    status: accessibilityStatus,
                    actions: .init(
                        request: {
                            permissionService.requestAccessibility()
                            refreshStatus()
                        },
                        openSettings: { permissionService.openAccessibilitySettings() }
                    )
                )
            }

            Section {
                Text(
                    "After granting Input Monitoring or Accessibility permissions,"
                    + " you may need to quit and reopen Uttr for the change to take effect."
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            refreshStatus()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshStatus()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        status: PermissionStatus,
        actions: PermissionActions
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(title)
                            .fontWeight(.medium)
                        statusBadge(status)
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if status != .granted {
                    Button("Request Access") {
                        actions.request()
                    }
                }
                Button("Open System Settings") {
                    actions.openSettings()
                }
            }
            .accessibilityIdentifier("permission-\(title.lowercased())")
            if status != .granted, let repair = actions.repair {
                Button("Not working? Repair & re-request") {
                    repair()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Text("Granted")
                .font(.caption)
                .foregroundStyle(.green)
        case .notGranted:
            Text("Not Granted")
                .font(.caption)
                .foregroundStyle(.red)
        case .unknown:
            Text("Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshStatus() {
        micStatus = permissionService.microphoneStatus()
        inputStatus = permissionService.inputMonitoringStatus()
        accessibilityStatus = permissionService.accessibilityStatus()
    }
}

private struct PermissionActions {
    let request: () -> Void
    let repair: (() -> Void)?
    let openSettings: () -> Void

    init(
        request: @escaping () -> Void,
        repair: (() -> Void)? = nil,
        openSettings: @escaping () -> Void
    ) {
        self.request = request
        self.repair = repair
        self.openSettings = openSettings
    }
}
