import Foundation

enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

struct ChatMessage: Equatable, Sendable {
    let role: ChatRole
    let content: String
}

/// 一次补全请求。与具体服务商无关，由 adapter 翻译成各家的报文。
struct ChatRequest: Sendable {
    let model: String
    let messages: [ChatMessage]
    /// 系统提示词。OpenAI 兼容协议会并入 messages，Anthropic 走顶层 system 字段。
    let system: String?
    let temperature: Double
    let maxTokens: Int
}

struct TokenUsage: Equatable, Sendable {
    let prompt: Int
    let completion: Int
}
