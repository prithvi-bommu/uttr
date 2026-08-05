import Testing
@testable import Uttr

@Suite("Hotkey")
struct HotkeyTests {
    @Test("default hotkey is Control-Option-Space")
    func defaultHotkey() {
        let hotkey = Hotkey.default
        #expect(hotkey.keyCode == 49)
        #expect(hotkey.modifiers == [.control, .option])
    }

    @Test("display string includes modifiers and key name")
    func displayString() {
        let hotkey = Hotkey.default
        let display = hotkey.displayString
        #expect(display.contains("Control"))
        #expect(display.contains("Option"))
        #expect(display.contains("Space"))
    }
}
