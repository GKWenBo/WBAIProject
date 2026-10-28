import Foundation

/// Anthropic Messages API 的报文结构，字段名与线上 JSON 保持一致（下划线命名）
enum AnthropicDTO {

    /// `/v1/messages` 请求体
    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        /// 与 OpenAI 不同，system 是顶层字段
        let system: String?
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
    }

    /// `message_start` 事件：携带输入 token 数
    struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable { let input_tokens: Int? }
            let usage: Usage?
        }
        let message: Message?
    }

    /// `content_block_start` 事件（目前未解码使用）
    struct ContentBlockStart: Decodable {
        struct Block: Decodable { let type: String? }
        let content_block: Block?
    }

    /// `content_block_delta` 事件：type 区分 text_delta / thinking_delta
    struct ContentBlockDelta: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
        }
        let delta: Delta?
    }

    /// `message_delta` 事件：携带停止原因与累计输出 token 数
    struct MessageDelta: Decodable {
        struct Delta: Decodable { let stop_reason: String? }
        struct Usage: Decodable { let output_tokens: Int? }
        let delta: Delta?
        let usage: Usage?
    }

    /// 流内 `error` 事件的报文
    struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let type: String?
            let message: String?
        }
        let error: Payload?
    }
}
