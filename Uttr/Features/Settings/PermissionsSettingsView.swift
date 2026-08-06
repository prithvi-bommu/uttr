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
                    requestAction: {
                        Task { @MainActor in
                            micStatus = await permissionService.requestMicrophone()
                        }
                    },
                    action: { permissionService.openMicrophoneSettings() }
                )

                permissionRowWithRepair(
                    title: "Input Monitoring",
                    description: "Required to detect your global dictation shortcut.",
                    status: inputStatus,
                    requestAction: {
                        permissionService.requestInputMonitoring()
                        refreshStatus()
                    },
                    action: { permissionService.openInputMonitoringSettings() }
                )

                permissionRow(
                    title: "Accessibility",
                    description: "Required to paste transcribed text into other applications.",
                    status: accessibilityStatus,
                    requestAction: {
                        permissionService.requestAccessibility()
                        refreshStatus()
                    },
                    action: { permissionService.openAccessibilitySettings() }
                )
            }

            Section {
                Text("After granting Input Monitoring or Accessibility permissions, you may need to quit and reopen Uttr for the change to take effect.")
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
            // Re-check after the user returns from System Settings (spec §9).
            refreshStatus()
        }
    }

    @ViewBuilder
    private func permissionRowWithRepair(
        title: String,
        description: String,
        status: PermissionStatus,
        requestAction: @escaping () -> Void,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            permissionRow(title: title, description: description, status: status,
                          requestAction: requestAction, action: action)
            if status != .granted {
                Button("Uttr missing from the pane? Repair & re-request") {
                    permissionService.repairInputMonitoring()
                    refreshStatus()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        description: String,
        status: PermissionStatus,
        requestAction: @escaping () -> Void,
        action: @escaping () -> Void
    ) -> some View {
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
                    requestAction()
                }
            }
            Button("Open System Settings") {
                action()
            }
        }
        .accessibilityIdentifier("permission-\(title.lowercased())")
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
