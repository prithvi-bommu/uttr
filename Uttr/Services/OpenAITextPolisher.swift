import Foundation

/// OpenAI transcript cleanup using the chat-completions API. Only the final
/// transcript is included in the request; audio and app metadata never leave
/// the device.
struct OpenAITextPolisher: TextPolisher {
    let config: ProviderConfig
    let timeout: TimeInterval
    var http: HTTPRequesting = URLSessionHTTPRequester()

    func polish(_ transcript: String) async throws -> String {
        var request = URLRequest(
            url: URL(string: "https://api.openai.com/v1/chat/completions")!,
            timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": transcript],
            ],
        ])

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw CloudPolishError.requestFailed(status: status)
        }
        return try Self.extractText(from: data)
    }

    func testConnection() async throws -> PolishTestResult {
        await PolishKeyTester(http: http).test(
            provider: .openAI, config: config, timeoutSeconds: Int(timeout))
    }

    static func extractText(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw CloudPolishError.invalidResponse }

        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CloudPolishError.emptyResponse }
        return text
    }

    private static let systemPrompt = """
    Clean up this dictated transcript. Preserve its meaning and tone, remove \
    obvious filler or repetition, and fix punctuation and capitalization. \
    Return only the cleaned transcript with no explanation or markdown.
    """
}
