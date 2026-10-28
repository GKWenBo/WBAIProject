import Foundation

/// 支持的服务商，以及各自的默认地址与可选模型
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

    /// 默认模型取本地推荐清单第一个；可选列表见 `ModelCatalogService`
    var defaultModel: String { BundledModelCatalog.defaultModel(for: self) }

    /// DeepSeek 与 OpenAI 共用 OpenAI 兼容协议，只有 Anthropic 走自己的报文格式。
    var usesAnthropicProtocol: Bool { self == .anthropic }
}

/// 发起一次请求所需的服务商配置快照
struct ProviderConfig: Equatable, Sendable {
    let kind: ProviderKind
    let baseURL: URL
    let apiKey: String
    let model: String
}
