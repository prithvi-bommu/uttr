import Foundation
import OSLog

/// Turns a spoken prompt (already transcribed locally) into generated content.
/// Only the transcribed *text* ever leaves the machine — never audio.
protocol AIContentGenerating: Sendable {
    func generate(prompt: String) async throws -> String
}

enum AIContentError: LocalizedError {
    case notConfigured(String)
    case requestFailed(status: Int, detail: String)
    case emptyResponse
    case cliFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let what): "AI provider not configured: \(what)"
        case .requestFailed(let status, let detail): "AI request failed (HTTP \(status)): \(detail)"
        case .emptyResponse: "The AI returned an empty response."
        case .cliFailed(let code, let stderr): "AI command failed (exit \(code)): \(stderr)"
        }
    }
}

/// Builds the configured provider. All providers are generic mechanisms;
/// which backend they talk to is purely the user's local configuration.
enum AIContentProviderFactory {
    static func make(config: AIContentConfig) -> AIContentGenerating {
        switch config.provider {
        case .httpEndpoint:
            return OpenAICompatibleProvider(
                config: config.http,
                systemPrompt: config.systemPrompt,
                timeout: TimeInterval(config.timeoutSeconds))
        case .anthropic:
            return AnthropicProvider(
                config: config.anthropic,
                systemPrompt: config.systemPrompt,
                timeout: TimeInterval(config.timeoutSeconds))
        case .commandLine:
            return CLIProvider(
                config: config.cli,
                systemPrompt: config.systemPrompt,
                timeout: TimeInterval(config.timeoutSeconds))
        }
    }
}

// MARK: - OpenAI-compatible chat completions (configurable base URL)

/// Speaks the OpenAI `/chat/completions` wire format against any base URL:
/// api.openai.com, a local Ollama (`http://localhost:11434/v1`), LiteLLM,
/// or any other compatible server.
struct OpenAICompatibleProvider: AIContentGenerating {
    let config: HTTPProviderConfig
    let systemPrompt: String
    let timeout: TimeInterval
    var http: HTTPRequesting = URLSessionHTTPRequester()

    func generate(prompt: String) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !base.isEmpty, let url = URL(string: "\(base)/chat/completions") else {
            throw AIContentError.notConfigured("invalid base URL")
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = config.apiKey.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": prompt],
            ],
        ])

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw AIContentError.requestFailed(
                status: status,
                detail: Self.errorDetail(from: data))
        }
        return try Self.extractText(from: data)
    }

    /// Parses `choices[0].message.content`. Static and pure for testability.
    static func extractText(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw AIContentError.emptyResponse }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIContentError.emptyResponse }
        return text
    }

    static func errorDetail(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return String(data: data.prefix(200), encoding: .utf8) ?? "unreadable body"
    }
}

// MARK: - Anthropic messages API

struct AnthropicProvider: AIContentGenerating {
    let config: ProviderConfig
    let systemPrompt: String
    let timeout: TimeInterval
    var http: HTTPRequesting = URLSessionHTTPRequester()

    func generate(prompt: String) async throws -> String {
        let key = config.apiKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw AIContentError.notConfigured("missing API key") }

        var request = URLRequest(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [["role": "user", "content": prompt]],
        ])

        let (data, status) = try await http.send(request)
        guard (200...299).contains(status) else {
            throw AIContentError.requestFailed(
                status: status,
                detail: OpenAICompatibleProvider.errorDetail(from: data))
        }
        return try Self.extractText(from: data)
    }

    /// Parses `content[0].text`. Static and pure for testability.
    static func extractText(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw AIContentError.emptyResponse }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIContentError.emptyResponse }
        return trimmed
    }
}

// MARK: - Local CLI backend

/// Runs a user-configured local executable. The combined system prompt and
/// user prompt is written to stdin (or substituted for "{prompt}" in the
/// arguments); trimmed stdout is the response. A generic mechanism — which
/// tool it runs is entirely the user's local configuration.
struct CLIProvider: AIContentGenerating {
    let config: CLIProviderConfig
    let systemPrompt: String
    let timeout: TimeInterval

    func generate(prompt: String) async throws -> String {
        let path = config.executablePath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { throw AIContentError.notConfigured("missing executable path") }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw AIContentError.notConfigured("not executable: \(path)")
        }

        let fullPrompt = systemPrompt.isEmpty ? prompt : "\(systemPrompt)\n\n\(prompt)"
        let usesPlaceholder = config.arguments.contains { $0.contains("{prompt}") }
        let arguments = config.arguments.map {
            $0.replacingOccurrences(of: "{prompt}", with: fullPrompt)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if !usesPlaceholder {
            let stdin = Pipe()
            process.standardInput = stdin
            try process.run()
            stdin.fileHandleForWriting.write(Data(fullPrompt.utf8))
            stdin.fileHandleForWriting.closeFile()
        } else {
            try process.run()
        }

        // Enforce the timeout without blocking the caller's executor.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw AIContentError.requestFailed(status: 0, detail: "command timed out")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let output = String(
            data: stdout.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let errText = String(
                data: stderr.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8)?.prefix(300) ?? ""
            throw AIContentError.cliFailed(
                exitCode: process.terminationStatus, stderr: String(errText))
        }
        guard !output.isEmpty else { throw AIContentError.emptyResponse }
        return output
    }
}
