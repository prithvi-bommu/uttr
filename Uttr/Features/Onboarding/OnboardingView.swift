import Combine
import SwiftUI

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    @State private var showSkipConfirmation = false
    @State private var micStatus: PermissionStatus = .unknown
    @State private var inputStatus: PermissionStatus = .unknown
    @State private var accessibilityStatus: PermissionStatus = .unknown
    let permissionService: PermissionChecking
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(30)

            Divider()

            HStack {
                if step != .welcome {
                    Button("Back") {
                        step = step.previous
                    }
                }

                Spacer()

                Button("Skip Setup") {
                    showSkipConfirmation = true
                }
                .foregroundStyle(.secondary)

                if step == .done {
                    Button("Get Started") {
                        onComplete()
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("Next") {
                        step = step.next
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .onAppear {
            refreshStatuses()
        }
        .onChange(of: step) {
            refreshStatuses()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            // Re-check after the user returns from System Settings (spec §9).
            refreshStatuses()
        }
        .alert("Skip Setup?", isPresented: $showSkipConfirmation) {
            Button("Skip") {
                onComplete()
            }
            Button("Continue Setup", role: .cancel) {}
        } message: {
            Text("Uttr cannot dictate until the required permissions are granted.")
        }
    }

    private func refreshStatuses() {
        micStatus = permissionService.microphoneStatus()
        inputStatus = permissionService.inputMonitoringStatus()
        accessibilityStatus = permissionService.accessibilityStatus()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .microphone:
            microphoneStep
        case .inputMonitoring:
            inputMonitoringStep
        case .accessibility:
            accessibilityStep
        case .done:
            doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Welcome to Uttr")
                .font(.title)
                .fontWeight(.bold)

            Text("Uttr is a hold-to-talk dictation app. Press and hold your shortcut to record, then release to transcribe and paste — all processed locally on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var microphoneStep: some View {
        permissionStep(
            icon: "mic.fill",
            title: "Microphone Access",
            description: "Uttr needs microphone access to capture your voice while you hold the dictation shortcut. Audio is processed entirely on your Mac and never leaves your device.",
            status: micStatus,
            requestLabel: "Allow Microphone Access",
            requestAction: {
                Task { @MainActor in
                    micStatus = await permissionService.requestMicrophone()
                }
            },
            action: { permissionService.openMicrophoneSettings() },
            actionLabel: "Open System Settings"
        )
    }

    private var inputMonitoringStep: some View {
        permissionStep(
            icon: "keyboard",
            title: "Input Monitoring",
            description: "Uttr needs Input Monitoring to detect your global dictation shortcut, even when other apps are focused.",
            status: inputStatus,
            requestLabel: "Request Access",
            requestAction: {
                permissionService.requestInputMonitoring()
                refreshStatuses()
            },
            action: { permissionService.openInputMonitoringSettings() },
            actionLabel: "Open System Settings",
            note: "After granting, quit and reopen Uttr for the change to take effect."
        )
    }

    private var accessibilityStep: some View {
        permissionStep(
            icon: "universal.access",
            title: "Accessibility",
            description: "Uttr needs Accessibility access to paste transcribed text into other applications using a simulated keyboard shortcut.",
            status: accessibilityStatus,
            requestLabel: "Request Access",
            requestAction: {
                permissionService.requestAccessibility()
                refreshStatuses()
            },
            action: { permissionService.openAccessibilitySettings() },
            actionLabel: "Open System Settings",
            note: "After granting, quit and reopen Uttr for the change to take effect."
        )
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("You're All Set")
                .font(.title)
                .fontWeight(.bold)

            Text("Your default dictation shortcut is:")
                .foregroundStyle(.secondary)

            Text("Control + Option + Space")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("You can change this shortcut anytime in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func permissionStep(
        icon: String,
        title: String,
        description: String,
        status: PermissionStatus,
        requestLabel: String,
        requestAction: @escaping () -> Void,
        action: @escaping () -> Void,
        actionLabel: String,
        note: String? = nil
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text(title)
                .font(.title2)
                .fontWeight(.bold)

            Text(description)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack {
                statusLabel(status)
                Spacer()
                if status != .granted {
                    Button(requestLabel) {
                        requestAction()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(actionLabel) {
                    action()
                }
            }
            .padding()
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private func statusLabel(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .notGranted:
            Label("Not Granted", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .unknown:
            Label("Check Required", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case microphone
    case inputMonitoring
    case accessibility
    case done

    var next: OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? .done
    }

    var previous: OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? .welcome
    }
}
