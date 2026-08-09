import Foundation
import Testing
@testable import Uttr

@Suite("WindowFocus")
@MainActor
struct WindowFocusTests {

    @Test("identifier matching is case-insensitive containment")
    func matching() {
        // SwiftUI embeds the scene id in the window identifier.
        #expect(WindowFocus.identifierMatches("onboarding-AppWindow-1", marker: "onboarding"))
        #expect(WindowFocus.identifierMatches("com_apple_SwiftUI_Settings_window", marker: "settings"))
        #expect(WindowFocus.identifierMatches("Diagnostics-AppWindow-1", marker: "diagnostics"))
        #expect(!WindowFocus.identifierMatches("onboarding-AppWindow-1", marker: "settings"))
        #expect(!WindowFocus.identifierMatches(nil, marker: "settings"))
        #expect(!WindowFocus.identifierMatches("", marker: "settings"))
    }
}
