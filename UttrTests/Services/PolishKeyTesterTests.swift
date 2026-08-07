import Foundation
import Testing
@testable import Uttr

@Suite("PolishKeyTester")
struct PolishKeyTesterTests {

    // MARK: - Status mapping (pure)

    @Test("maps HTTP status codes to results")
    func statusMapping() {
        #expect(PolishKeyTester.result(forStatus: 200) == .success)
        #expect(PolishKeyTester.result(forStatus: 204) == .success)
        #expect(PolishKeyTester.result(forStatus: 401) == .invalidKey)
        #expect(PolishKeyTester.result(forStatus: 403) == .invalidKey)
        #expect(PolishKeyTester.result(forStatus: 404) == .unsupportedModel)
        #expect(PolishKeyTester.result(forStatus: 429) == .rateLimited)
        #expect(PolishKeyTester.result(forStatus: 500) == .unavailable)
        #expect(PolishKeyTester.result(forStatus: 503) == .unavailable)
        #expect(PolishKeyTester.result(forStatus: 418) == .unknownError("HTTP 418"))
    }

    // MARK: - Request building (pure)

    @Test("builds an OpenAI models request with bearer auth")
    func openAIRequest() throws {
        let request = try #require(PolishKeyTester.request(
            provider: .openAI,
            config: ProviderConfig(apiKey: " sk-test ", model: "gpt-5.6-luna"),
            timeout: 8))
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models/gpt-5.6-luna")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.httpMethod == "GET")
    }

    @Test("builds an Anthropic models request with x-api-key")
    func anthropicRequest() throws {
        let request = try #require(PolishKeyTester.request(
            provider: .anthropic,
            config: ProviderConfig(apiKey: "sk-ant", model: "claude-haiku-4-5"),
            timeout: 8))
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models/claude-haiku-4-5")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") != nil)
    }

    @Test("no provider yields no request")
    func noProvider() {
        #expect(PolishKeyTester.request(
            provider: .none,
            config: ProviderConfig(apiKey: "k", model: "m"),
            timeout: 8) == nil)
    }

    // MARK: - End-to-end with mock HTTP

    final class MockHTTP: HTTPRequesting, @unchecked Sendable {
        var status = 200
        var error: Error?
        private(set) var lastRequest: URLRequest?

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            lastRequest = request
            if let error { throw error }
            return (Data(), status)
        }
    }

    @Test("valid key reports success")
    func validKey() async {
        let http = MockHTTP()
        let tester = PolishKeyTester(http: http)
        let result = await tester.test(
            provider: .openAI,
            config: ProviderConfig(apiKey: "sk", model: "m"),
            timeoutSeconds: 8)
        #expect(result == .success)
        #expect(http.lastRequest != nil)
    }

    @Test("401 reports invalid key")
    func invalidKey() async {
        let http = MockHTTP()
        http.status = 401
        let result = await PolishKeyTester(http: http).test(
            provider: .anthropic,
            config: ProviderConfig(apiKey: "bad", model: "m"),
            timeoutSeconds: 8)
        #expect(result == .invalidKey)
    }

    @Test("URLError timeout maps to .timeout")
    func timeout() async {
        let http = MockHTTP()
        http.error = URLError(.timedOut)
        let result = await PolishKeyTester(http: http).test(
            provider: .openAI,
            config: ProviderConfig(apiKey: "sk", model: "m"),
            timeoutSeconds: 1)
        #expect(result == .timeout)
    }

    @Test("offline maps to .unavailable")
    func offline() async {
        let http = MockHTTP()
        http.error = URLError(.notConnectedToInternet)
        let result = await PolishKeyTester(http: http).test(
            provider: .openAI,
            config: ProviderConfig(apiKey: "sk", model: "m"),
            timeoutSeconds: 8)
        #expect(result == .unavailable)
    }

    @Test("no provider reports unknown error, no request sent")
    func noProviderTest() async {
        let http = MockHTTP()
        let result = await PolishKeyTester(http: http).test(
            provider: .none,
            config: ProviderConfig(apiKey: "sk", model: "m"),
            timeoutSeconds: 8)
        #expect(result == .unknownError("No provider selected"))
        #expect(http.lastRequest == nil)
    }
}
