import SwiftUI

struct PermissionAlertInfo: Identifiable, Equatable {
    let id = UUID()
    let blocker: PermissionBlocker

    var title: String {
        switch blocker {
        case .microphone: "Microphone Permission Required"
        case .inputMonitoring: "Input Monitoring Permission Required"
        case .accessibility: "Accessibility Permission Required"
        }
    }

    var message: String {
        switch blocker {
        case .microphone:
            "Uttr needs microphone access to capture your voice during dictation. Audio is processed locally and never leaves your Mac."
        case .inputMonitoring:
            "Uttr needs Input Monitoring permission to detect your global dictation shortcut. You may need to quit and reopen Uttr after granting this permission."
        case .accessibility:
            "Uttr needs Accessibility permission to paste transcribed text into other applications. You may need to quit and reopen Uttr after granting this permission."
        }
    }

    static func == (lhs: PermissionAlertInfo, rhs: PermissionAlertInfo) -> Bool {
        lhs.blocker == rhs.blocker
    }
}
