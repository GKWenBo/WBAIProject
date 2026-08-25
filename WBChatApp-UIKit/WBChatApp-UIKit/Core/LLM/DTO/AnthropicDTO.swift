import Foundation

enum AnthropicDTO {

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

    struct MessageStart: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable { let input_tokens: Int? }
            let usage: Usage?
        }
        let message: Message?
    }

    struct ContentBlockStart: Decodable {
        struct Block: Decodable { let type: String? }
        let content_block: Block?
    }

    struct ContentBlockDelta: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
            let thinking: String?
        }
        let delta: Delta?
    }

    struct MessageDelta: Decodable {
        struct Delta: Decodable { let stop_reason: String? }
        struct Usage: Decodable { let output_tokens: Int? }
        let delta: Delta?
        let usage: Usage?
    }

    struct ErrorEnvelope: Decodable {
        struct Payload: Decodable {
            let type: String?
            let message: String?
        }
        let error: Payload?
    }
}
