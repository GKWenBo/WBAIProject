import Foundation

enum OpenAIDTO {

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

    struct StreamResponse: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                let reasoning_content: String?
            }
            let delta: Delta?
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
