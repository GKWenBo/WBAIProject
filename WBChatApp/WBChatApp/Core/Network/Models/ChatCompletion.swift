//
//  ChatCompletion.swift
//  WBChatApp
//

import Foundation

/// OpenAI 兼容的聊天消息负载（DeepSeek 使用相同格式）
nonisolated struct ChatMessagePayload: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

/// `POST /chat/completions` 请求体
nonisolated struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [ChatMessagePayload]
    let stream: Bool
    let temperature: Double?
}

/// SSE 流式返回的单个 chunk（`data: {...}` 的 JSON 部分）
nonisolated struct ChatCompletionChunk: Decodable, Sendable {

    struct Choice: Decodable, Sendable {

        struct Delta: Decodable, Sendable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }

        let delta: Delta?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}

/// 上层消费的流式增量
nonisolated struct StreamChunk: Equatable, Sendable {
    var deltaContent: String?
    var deltaReasoning: String?
    var finishReason: String?
}
