//
//  SSEParser.swift
//  WBChatApp
//

import Foundation

/// SSE（Server-Sent Events）行解析器
///
/// DeepSeek 流式接口按行返回 `data: {...json...}`，结束标记为 `data: [DONE]`。
/// 纯函数实现，无状态，便于单元测试。
nonisolated enum SSEParser {

    enum Event: Equatable {
        case chunk(StreamChunk)
        case done
    }

    /// 解析单行 SSE 文本
    /// - Returns: 有效事件；空行、注释行或无法识别的行返回 `nil`
    static func parse(line: String) -> Event? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }

        let payload = trimmed.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        guard payload != "[DONE]" else { return .done }

        guard let data = payload.data(using: .utf8),
              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
              let choice = chunk.choices.first else {
            return nil
        }
        return .chunk(StreamChunk(
            deltaContent: choice.delta?.content,
            deltaReasoning: choice.delta?.reasoningContent,
            finishReason: choice.finishReason
        ))
    }
}
