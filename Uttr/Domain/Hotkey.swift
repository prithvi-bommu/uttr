import Foundation

struct Hotkey: Equatable, Sendable {
    let keyCode: UInt16
    let modifiers: Set<ModifierKey>

    static let `default` = Hotkey(
        keyCode: 49,
        modifiers: [.control, .option]
    )

    /// Virtual key code of the Fn/Globe key (surfaces via flagsChanged).
    static let fnGlobeKeyCode: UInt16 = 63

    /// Bare Fn/Globe hold-to-talk hotkey (ADR-008). Fn is only supported
    /// alone — never combined with other keys or as a modifier.
    var isFnGlobe: Bool {
        keyCode == Self.fnGlobeKeyCode && modifiers.isEmpty
    }

    var displayString: String {
        if isFnGlobe {
            return "🌐 Globe (Fn)"
        }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Control") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.command) { parts.append("Command") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: " + ")
    }

    private static func keyName(for keyCode: UInt16) -> String {
        switch keyCode {
        case 49: "Space"
        case 36: "Return"
        case 48: "Tab"
        case 51: "Delete"
        case 63: "🌐/Fn"
        case 76: "Enter"
        default: "Key(\(keyCode))"
        }
    }
}
