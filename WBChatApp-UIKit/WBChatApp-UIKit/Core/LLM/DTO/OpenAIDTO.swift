import Foundation

/// OpenAI 兼容协议的报文结构，字段名与线上 JSON 保持一致（下划线命名）
enum OpenAIDTO {

    /// `/v1/chat/completions` 请求体
    struct RequestBody: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [Message]
        let stream: Bool
        let temperature: Double
        let max_tokens: Int
        /// 要求末帧带上用量统计
        let stream_options: StreamOptions?

        struct StreamOptions: Encodable {
            let include_usage: Bool
        }
    }

    /// 流式响应中的一帧
    struct StreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                /// 正文增量
                let content: String?
                /// 思考增量（DeepSeek reasoner 专有）
                let reasoning_content: String?
            }
            let delta: Delta?
            /// 非空表示本轮生成结束（stop / length 等）
            let finish_reason: String?
        }
        struct Usage: Decodable {
            let prompt_tokens: Int
            let completion_tokens: Int
        }
        let choices: [Choice]?
        let usage: Usage?
    }

    /// 错误响应体，用于把服务端文案带给用户
    struct ErrorResponse: Decodable {
        struct Payload: Decodable { let message: String? }
        let error: Payload?
    }
}
