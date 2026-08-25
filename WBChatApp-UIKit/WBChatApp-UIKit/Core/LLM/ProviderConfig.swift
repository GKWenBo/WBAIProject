import Foundation

enum ProviderKind: String, CaseIterable, Codable, Sendable {
    case deepSeek
    case openAI
    case anthropic

    var displayName: String {
        switch self {
        case .deepSeek:  return "DeepSeek"
        case .openAI:    return "OpenAI"
        case .anthropic: return "Anthropic"
        }
    }

    var defaultBaseURL: URL {
        switch self {
        case .deepSeek:  return URL(string: "https://api.deepseek.com")!
        case .openAI:    return URL(string: "https://api.openai.com")!
        case .anthropic: return URL(string: "https://api.anthropic.com")!
        }
    }

    var availableModels: [String] {
        switch self {
        case .deepSeek:  return ["deepseek-chat", "deepseek-reasoner"]
        case .openAI:    return ["gpt-4o", "gpt-4o-mini"]
        case .anthropic: return ["claude-sonnet-5", "claude-opus-5", "claude-haiku-4-5-20251001"]
        }
    }

    var defaultModel: String { availableModels[0] }

    /// DeepSeek 与 OpenAI 共用 OpenAI 兼容协议，只有 Anthropic 走自己的报文格式。
    var usesAnthropicProtocol: Bool { self == .anthropic }
}

struct ProviderConfig: Equatable, Sendable {
    let kind: ProviderKind
    let baseURL: URL
    let apiKey: String
    let model: String
}
