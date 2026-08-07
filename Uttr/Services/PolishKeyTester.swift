import Foundation
import OSLog

/// Minimal HTTP seam so the key tester is unit-testable without network.
protocol HTTPRequesting: Sendable {
    /// Performs the request and returns the body plus HTTP status code.
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionHTTPRequester: HTTPRequesting {
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }
}

/// Validates a cloud-polish API key (and model name) with one cheap request
/// to the provider's model endpoint. Sends ONLY the key and model identifier —
/// never any transcript text.
struct PolishKeyTester: Sendable {
    private let http: HTTPRequesting
    private let logger = Logger(subsystem: "com.uttr.app", category: "polish")

    init(http: HTTPRequesting = URLSessionHTTPRequester()) {
        self.http = http
    }

    func test(
        provider: PolishProvider,
        config: ProviderConfig,
        timeoutSeconds: Int
    ) async -> PolishTestResult {
        guard let request = Self.request(
            provider: provider, config: config,
            timeout: TimeInterval(timeoutSeconds)
        ) else {
            return .unknownError("No provider selected")
        }

        do {
            let (_, status) = try await http.send(request)
            let result = Self.result(forStatus: status)
            logger.info("Key test (\(provider.rawValue, privacy: .public)): HTTP \(status, privacy: .public)")
            return result
        } catch let error as URLError where error.code == .timedOut {
            return .timeout
        } catch let error as URLError where
            error.code == .notConnectedToInternet ||
            error.code == .cannotFindHost ||
            error.code == .cannotConnectToHost ||
            error.code == .networkConnectionLost {
            return .unavailable
        } catch {
            return .unknownError(error.localizedDescription)
        }
    }

    /// Pure status-code mapping, unit-testable without any I/O.
    static func result(forStatus status: Int) -> PolishTestResult {
        switch status {
        case 200...299: .success
        case 401, 403: .invalidKey
        case 404: .unsupportedModel
        case 429: .rateLimited
        case 500...599: .unavailable
        default: .unknownError("HTTP \(status)")
        }
    }

    /// Builds the provider-specific model-lookup request. Returns nil for
    /// `.none`. Pure and unit-testable.
    static func request(
        provider: PolishProvider,
        config: ProviderConfig,
        timeout: TimeInterval
    ) -> URLRequest? {
        let key = config.apiKey.trimmingCharacters(in: .whitespaces)
        let model = config.model.trimmingCharacters(in: .whitespaces)

        let url: URL
        var headers: [String: String]
        switch provider {
        case .none:
            return nil
        case .openAI:
            url = URL(string: "https://api.openai.com/v1/models/\(model)")!
            headers = ["Authorization": "Bearer \(key)"]
        case .anthropic:
            url = URL(string: "https://api.anthropic.com/v1/models/\(model)")!
            headers = ["x-api-key": key, "anthropic-version": "2023-06-01"]
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }
}

extension PolishTestResult {
    /// Human-readable outcome for the Settings UI.
    var displayText: String {
        switch self {
        case .success: "✓ Key is valid and the model is available."
        case .invalidKey: "✗ The API key was rejected. Check the key."
        case .rateLimited: "✗ Rate limited — the key works, but try again later."
        case .unavailable: "✗ Could not reach the provider. Check your connection."
        case .timeout: "✗ The request timed out."
        case .unsupportedModel: "✗ The key works, but this model name was not found."
        case .unknownError(let detail): "✗ Failed: \(detail)"
        }
    }
}
