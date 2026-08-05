import Foundation
import Testing
@testable import Uttr

@Suite("ConfigurationStore")
@MainActor
struct ConfigurationStoreTests {

    private func makeStore(fileSystem: MockFileSystem = MockFileSystem()) -> (ConfigurationStore, MockFileSystem, URL) {
        let url = URL(fileURLWithPath: "/tmp/uttr-test/config.json")
        let store = ConfigurationStore(configURL: url, fileSystem: fileSystem)
        return (store, fileSystem, url)
    }

    // MARK: - Default behavior

    @Test("defaults when no config file exists")
    func defaultsWithNoFile() {
        let (store, _, _) = makeStore()
        store.load()
        #expect(store.settings == .default)
    }

    @Test("defaults when config file is malformed")
    func defaultsWithMalformedFile() {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/uttr-test/config.json")
        fs.files[url.path] = Data("not json".utf8)
        let store = ConfigurationStore(configURL: url, fileSystem: fs)
        store.load()
        #expect(store.settings == .default)
    }

    // MARK: - Round-trip encoding

    @Test("save and load round-trips default settings")
    func roundTrip() throws {
        let (store, fs, url) = makeStore()
        try store.save()

        let store2 = ConfigurationStore(configURL: url, fileSystem: fs)
        store2.load()
        #expect(store2.settings == UttrSettings.default)
    }

    @Test("save and load round-trips modified settings")
    func roundTripModified() throws {
        let (store, fs, url) = makeStore()
        try store.update { $0.startAtLogin = true }

        let store2 = ConfigurationStore(configURL: url, fileSystem: fs)
        store2.load()
        #expect(store2.settings.startAtLogin == true)
    }

    // MARK: - File permissions

    @Test("save creates directory with 0700 permissions")
    func directoryPermissions() throws {
        let (store, fs, _) = makeStore()
        try store.save()
        let dirPath = "/tmp/uttr-test"
        let attrs = fs.directories[dirPath]
        #expect(attrs?[.posixPermissions] as? Int == 0o700)
    }

    @Test("save sets file permissions to 0600")
    func filePermissions() throws {
        let (store, fs, url) = makeStore()
        try store.save()
        let attrs = fs.fileAttributes[url.path]
        #expect(attrs?[.posixPermissions] as? Int == 0o600)
    }

    // MARK: - Atomic write

    @Test("save produces final file without leftover temp file")
    func atomicWriteCleanup() throws {
        let (store, fs, _) = makeStore()
        try store.save()
        #expect(fs.files["/tmp/uttr-test/config.json"] != nil)
        #expect(fs.files["/tmp/uttr-test/config.json.tmp"] == nil)
    }

    // MARK: - Schema version

    @Test("unsupported schema version preserves file and uses defaults")
    func unsupportedSchemaVersion() {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/uttr-test/config.json")
        var settings = UttrSettings.default
        settings.schemaVersion = 99
        let data = try! JSONEncoder().encode(settings)
        fs.files[url.path] = data

        let store = ConfigurationStore(configURL: url, fileSystem: fs)
        store.load()
        #expect(store.settings == .default)
        #expect(fs.files[url.path] == data)
    }

    // MARK: - Validation (via update)

    @Test("validation rejects missing modifier")
    func rejectsNoModifier() {
        let (store, _, _) = makeStore()
        #expect(throws: UttrSettings.ValidationError.self) {
            try store.update { $0.hotkey.modifiers = [] }
        }
    }

    @Test("validation rejects zero key code")
    func rejectsZeroKeyCode() {
        let (store, _, _) = makeStore()
        #expect(throws: UttrSettings.ValidationError.self) {
            try store.update { $0.hotkey.keyCode = 0 }
        }
    }

    @Test("validation rejects polish enabled without key")
    func rejectsPolishWithoutKey() {
        let (store, _, _) = makeStore()
        #expect(throws: UttrSettings.ValidationError.self) {
            try store.update {
                $0.cloudPolish.enabled = true
                $0.cloudPolish.provider = .openAI
                $0.cloudPolish.openAI.apiKey = ""
            }
        }
    }

    @Test("validation rejects polish enabled without model")
    func rejectsPolishWithoutModel() {
        let (store, _, _) = makeStore()
        #expect(throws: UttrSettings.ValidationError.self) {
            try store.update {
                $0.cloudPolish.enabled = true
                $0.cloudPolish.provider = .openAI
                $0.cloudPolish.openAI.apiKey = "sk-test"
                $0.cloudPolish.openAI.model = ""
            }
        }
    }

    @Test("validation rejects timeout out of range")
    func rejectsTimeoutOutOfRange() {
        let (store, _, _) = makeStore()
        #expect(throws: UttrSettings.ValidationError.self) {
            try store.update { $0.cloudPolish.timeoutSeconds = 1 }
        }
    }

    @Test("validation accepts valid polish config")
    func acceptsValidPolish() throws {
        let (store, _, _) = makeStore()
        try store.update {
            $0.cloudPolish.enabled = true
            $0.cloudPolish.provider = .openAI
            $0.cloudPolish.openAI.apiKey = "sk-test"
            $0.cloudPolish.openAI.model = "gpt-5.6-luna"
        }
    }

    // MARK: - Sanitization

    @Test("unknown whisper model falls back to small.en")
    func unknownWhisperModelFallback() {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/uttr-test/config.json")
        var settings = UttrSettings.default
        settings.whisperModel = "large-v3"
        let data = try! JSONEncoder().encode(settings)
        fs.files[url.path] = data

        let store = ConfigurationStore(configURL: url, fileSystem: fs)
        store.load()
        #expect(store.settings.whisperModel == "small.en")
    }

    @Test("timeout clamped to valid range on load")
    func timeoutClampedOnLoad() {
        let fs = MockFileSystem()
        let url = URL(fileURLWithPath: "/tmp/uttr-test/config.json")
        var settings = UttrSettings.default
        settings.cloudPolish.timeoutSeconds = 100
        let data = try! JSONEncoder().encode(settings)
        fs.files[url.path] = data

        let store = ConfigurationStore(configURL: url, fileSystem: fs)
        store.load()
        #expect(store.settings.cloudPolish.timeoutSeconds == 20)
    }

    // MARK: - Update convenience

    @Test("update applies block and saves")
    func updateAppliesAndSaves() throws {
        let (store, fs, url) = makeStore()
        try store.update { $0.hasCompletedOnboarding = true }
        #expect(store.settings.hasCompletedOnboarding == true)
        #expect(fs.files[url.path] != nil)
    }
}
