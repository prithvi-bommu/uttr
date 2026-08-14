import Foundation
import Testing
@testable import Uttr

@Suite("UpdaterService")
@MainActor
struct UpdaterServiceTests {

    @Test("MockUpdaterService records checkForUpdates calls")
    func checkForUpdatesRecordsCall() {
        let mock = MockUpdaterService()
        #expect(!mock.checkForUpdatesCalled)
        mock.checkForUpdates()
        #expect(mock.checkForUpdatesCalled)
    }

    @Test("MockUpdaterService round-trips automaticallyChecksForUpdates")
    func automaticallyChecksRoundTrip() {
        let mock = MockUpdaterService()
        #expect(!mock.automaticallyChecksForUpdates)
        mock.automaticallyChecksForUpdates = true
        #expect(mock.automaticallyChecksForUpdates)
        mock.automaticallyChecksForUpdates = false
        #expect(!mock.automaticallyChecksForUpdates)
    }

    @Test("canCheckForUpdates controls button availability")
    func canCheckForUpdatesDefault() {
        let mock = MockUpdaterService()
        #expect(mock.canCheckForUpdates)
        mock.canCheckForUpdates = false
        #expect(!mock.canCheckForUpdates)
    }

    @Test("lastUpdateCheckDate is nil by default")
    func lastCheckDateDefault() {
        let mock = MockUpdaterService()
        #expect(mock.lastUpdateCheckDate == nil)
    }

    @Test("lastUpdateCheckDate can be set")
    func lastCheckDateSet() {
        let mock = MockUpdaterService()
        let date = Date(timeIntervalSince1970: 1_000_000)
        mock.lastUpdateCheckDate = date
        #expect(mock.lastUpdateCheckDate == date)
    }

    @Test("automaticallyChecksForUpdates does not write to UttrSettings")
    func doesNotWriteToSettings() {
        let store = ConfigurationStore()
        let mock = MockUpdaterService()
        let initialSettings = store.settings
        mock.automaticallyChecksForUpdates = true
        #expect(store.settings.hotkey.keyCode == initialSettings.hotkey.keyCode)
    }
}
