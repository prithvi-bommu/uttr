import AppKit
import Foundation

/// What macOS does when the 🌐/Fn key is pressed alone
/// (System Settings → Keyboard → "Press 🌐 key to").
enum FnGlobeAction: Equatable, Sendable {
    case doNothing            // 0 — required for Uttr's bare-Fn hotkey
    case changeInputSource    // 1
    case showEmojiAndSymbols  // 2
    case startDictation       // 3 (Apple's own dictation)
    case unknown              // key absent or unrecognized value

    var displayName: String {
        switch self {
        case .doNothing: "Do Nothing"
        case .changeInputSource: "Change Input Source"
        case .showEmojiAndSymbols: "Show Emoji & Symbols"
        case .startDictation: "Start Dictation"
        case .unknown: "Unknown"
        }
    }
}

/// Seam for reading the system Globe-key action (testable; the real value
/// lives in the com.apple.HIToolbox defaults suite, key AppleFnUsageType).
/// Uttr can only read this setting — changing it requires the user.
protocol FnUsageChecking: Sendable {
    func currentAction() -> FnGlobeAction
    func openKeyboardSettings()
}

struct RealFnUsageService: FnUsageChecking {
    func currentAction() -> FnGlobeAction {
        guard let defaults = UserDefaults(suiteName: "com.apple.HIToolbox"),
              defaults.object(forKey: "AppleFnUsageType") != nil
        else {
            return .unknown
        }
        switch defaults.integer(forKey: "AppleFnUsageType") {
        case 0: return .doNothing
        case 1: return .changeInputSource
        case 2: return .showEmojiAndSymbols
        case 3: return .startDictation
        default: return .unknown
        }
    }

    func openKeyboardSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
