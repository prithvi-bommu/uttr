import Foundation

protocol TextPolisher: Sendable {
    func polish(_ transcript: String) async throws -> String
    func testConnection() async throws -> PolishTestResult
}

enum PolishTestResult: Equatable {
    case success
    case invalidKey
    case rateLimited
    case unavailable
    case timeout
    case unsupportedModel
    case unknownError(String)
}
