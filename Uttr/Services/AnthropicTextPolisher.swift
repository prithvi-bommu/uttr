import Foundation

/// Anthropic transcript cleanup using the Messages API.
struct AnthropicTextPolisher: TextPolisher {
    let config: ProviderConfig
    let timeout: TimeInterval
    var http: HTTPRequesting = URLSessionHTTPRequester()

    func polish(_ transcript: String) async throws -> String {
        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "max_tokens": 4096,
            "system": Self.systemPrompt,
            "messages": [["role": "user", "content": transcript]],
        ])

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw CloudPolishError.requestFailed(status: status)
        }
        return try Self.extractText(from: data)
    }

    func testConnection() async throws -> PolishTestResult {
        await PolishKeyTester(http: http).test(
            provider: .anthropic, config: config, timeoutSeconds: Int(timeout))
    }

    static func extractText(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw CloudPolishError.invalidResponse }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudPolishError.emptyResponse }
        return trimmed
    }

    private static let systemPrompt = """
    Clean up this dictated transcript. Preserve its meaning and tone, remove \
    obvious filler or repetition, and fix punctuation and capitalization. \
    Return only the cleaned transcript with no explanation or markdown.
    """
}
