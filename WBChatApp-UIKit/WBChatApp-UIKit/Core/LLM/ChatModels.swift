import Foundation

/// 消息发言方，rawValue 直接作为请求报文里的 role
enum ChatRole: String, Codable, Sendable {
    case system, user, assistant
}

/// 发给模型的一条上下文消息
struct ChatMessage: Equatable, Sendable {
    let role: ChatRole
    let content: String
}

/// 一次补全请求。与具体服务商无关，由 adapter 翻译成各家的报文。
struct ChatRequest: Sendable {
    let model: String
    /// 历史上下文（不含 system）
    let messages: [ChatMessage]
    /// 系统提示词。OpenAI 兼容协议会并入 messages，Anthropic 走顶层 system 字段。
    let system: String?
    let temperature: Double
    let maxTokens: Int
}

/// token 用量：prompt 为输入，completion 为输出
struct TokenUsage: Equatable, Sendable {
    let prompt: Int
    let completion: Int
}
