import Foundation

/// 抹平两家协议差异后的统一流式事件。
/// ViewModel 及以上只认识这个类型。
enum StreamChunk: Equatable, Sendable {
    /// 正文增量
    case textDelta(String)
    /// 思考过程增量（DeepSeek reasoning_content / Anthropic thinking）
    case reasoningDelta(String)
    /// token 用量，通常在流末尾出现一次
    case usage(TokenUsage)
    /// 流正常结束
    case done(finishReason: String?)
}
