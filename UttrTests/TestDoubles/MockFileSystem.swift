import Foundation
@testable import Uttr

final class MockFileSystem: FileSystemProtocol, @unchecked Sendable {
    var files: [String: Data] = [:]
    var directories: [String: [FileAttributeKey: Any]] = [:]
    var fileAttributes: [String: [FileAttributeKey: Any]] = [:]
    var writeError: Error?
    var replaceError: Error?

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories[path] != nil
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]?) throws {
        directories[url.path] = attributes ?? [:]
    }

    func contents(atPath path: String) -> Data? {
        files[path]
    }

    func write(_ data: Data, to url: URL) throws {
        if let error = writeError { throw error }
        files[url.path] = data
    }

    func replaceItem(at originalURL: URL, withItemAt newURL: URL) throws {
        if let error = replaceError { throw error }
        files[originalURL.path] = files[newURL.path]
        files.removeValue(forKey: newURL.path)
    }

    func moveItem(at srcURL: URL, to dstURL: URL) throws {
        files[dstURL.path] = files[srcURL.path]
        files.removeValue(forKey: srcURL.path)
    }

    func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        fileAttributes[path] = attributes
    }
}
