import Foundation

enum CloudPolishError: LocalizedError, Equatable {
    case requestFailed(status: Int)
    case invalidResponse
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .requestFailed(let status):
            "Text polish request failed (HTTP \(status))."
        case .invalidResponse:
            "The text polish provider returned an invalid response."
        case .emptyResponse:
            "The text polish provider returned an empty response."
        }
    }
}

enum TextPolisherFactory {
    static func make(config: CloudPolishConfig) -> TextPolisher? {
        guard config.enabled, let providerConfig = activeProviderConfig(for: config) else {
            return nil
        }

        let timeout = TimeInterval(config.timeoutSeconds)
        switch config.provider {
        case .none:
            return nil
        case .openAI:
            return OpenAITextPolisher(config: providerConfig, timeout: timeout)
        case .anthropic:
            return AnthropicTextPolisher(config: providerConfig, timeout: timeout)
        }
    }

    private static func activeProviderConfig(for config: CloudPolishConfig) -> ProviderConfig? {
        let providerConfig: ProviderConfig
        switch config.provider {
        case .none:
            return nil
        case .openAI:
            providerConfig = config.openAI
        case .anthropic:
            providerConfig = config.anthropic
        }

        guard
            !providerConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !providerConfig.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return providerConfig
    }
}
