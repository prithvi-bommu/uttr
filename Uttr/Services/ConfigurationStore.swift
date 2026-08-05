import Foundation
import OSLog

protocol FileSystemProtocol: Sendable {
    func fileExists(atPath path: String) -> Bool
    func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]?) throws
    func contents(atPath path: String) -> Data?
    func write(_ data: Data, to url: URL) throws
    func replaceItem(at originalURL: URL, withItemAt newURL: URL) throws
    func moveItem(at srcURL: URL, to dstURL: URL) throws
    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws
}

struct RealFileSystem: FileSystemProtocol {
    func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]?) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories, attributes: attributes)
    }

    func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    func replaceItem(at originalURL: URL, withItemAt newURL: URL) throws {
        _ = try FileManager.default.replaceItemAt(originalURL, withItemAt: newURL)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try FileManager.default.moveItem(at: srcURL, to: dstURL)
    }

    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        try FileManager.default.setAttributes(attributes, ofItemAtPath: path)
    }
}

@MainActor
@Observable
final class ConfigurationStore {
    private(set) var settings: UttrSettings
    private let configURL: URL
    private let directoryURL: URL
    private let fileSystem: FileSystemProtocol
    private let logger = Logger(subsystem: "com.uttr.app", category: "config")

    init(fileSystem: FileSystemProtocol = RealFileSystem()) {
        self.fileSystem = fileSystem
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.directoryURL = appSupport.appendingPathComponent("Uttr", isDirectory: true)
        self.configURL = directoryURL.appendingPathComponent("config.json")
        self.settings = .default
    }

    init(configURL: URL, fileSystem: FileSystemProtocol) {
        self.fileSystem = fileSystem
        self.directoryURL = configURL.deletingLastPathComponent()
        self.configURL = configURL
        self.settings = .default
    }

    func load() {
        guard let data = fileSystem.contents(atPath: configURL.path) else {
            logger.info("No config file found, using defaults")
            return
        }

        do {
            var decoded = try JSONDecoder().decode(UttrSettings.self, from: data)
            if decoded.schemaVersion != 1 {
                logger.warning("Unsupported schema version \(decoded.schemaVersion), preserving file and using defaults")
                return
            }
            decoded.sanitize()
            settings = decoded
            logger.info("Configuration loaded")
        } catch {
            logger.error("Malformed config file, using defaults: \(error.localizedDescription)")
            settings = .default
        }
    }

    func save() throws {
        try settings.validate()

        try ensureDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)

        let tempURL = directoryURL.appendingPathComponent("config.json.tmp")
        try fileSystem.write(data, to: tempURL)
        try fileSystem.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)

        if fileSystem.fileExists(atPath: configURL.path) {
            try fileSystem.replaceItem(at: configURL, withItemAt: tempURL)
        } else {
            try fileSystem.moveItem(at: tempURL, to: configURL)
        }

        try fileSystem.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        logger.info("Configuration saved")
    }

    func update(_ block: (inout UttrSettings) -> Void) throws {
        var updated = settings
        block(&updated)
        settings = updated
        try save()
    }

    private func ensureDirectory() throws {
        if !fileSystem.fileExists(atPath: directoryURL.path) {
            try fileSystem.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            logger.info("Created config directory")
        }
    }
}
