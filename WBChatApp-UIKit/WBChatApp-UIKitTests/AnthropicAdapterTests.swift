import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("Anthropic 协议适配")
struct AnthropicAdapterTests {

    private func chunks(_ events: [(String, String)]) throws -> [StreamChunk] {
        var mapper = AnthropicChunkMapper()
        var result: [StreamChunk] = []
        for (type, data) in events {
            result += try mapper.map(SSEEvent(event: type, data: data, id: nil, retry: nil))
        }
        return result
    }

    @Test("text_delta 映射为正文增量")
    func textDelta() throws {
        let result = try chunks([
            ("content_block_delta", #"{"index":0,"delta":{"type":"text_delta","text":"你好"}}"#)
        ])
        #expect(result == [.textDelta("你好")])
    }

    @Test("thinking_delta 映射为思考增量")
    func thinkingDelta() throws {
        let result = try chunks([
            ("content_block_delta", #"{"index":0,"delta":{"type":"thinking_delta","thinking":"先想想"}}"#)
        ])
        #expect(result == [.reasoningDelta("先想想")])
    }

    @Test("message_start 与 content_block_start 本身不产生事件")
    func startEventsAreSilent() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":5,"output_tokens":0}}}"#),
            ("content_block_start", #"{"index":0,"content_block":{"type":"text","text":""}}"#),
        ])
        #expect(result.isEmpty)
    }

    @Test("message_delta 带出用量与停止原因")
    func messageDelta() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":7,"output_tokens":0}}}"#),
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":21}}"#),
        ])
        #expect(result == [.usage(TokenUsage(prompt: 7, completion: 21))])
    }

    @Test("message_stop 结束流并带出停止原因")
    func messageStop() throws {
        let result = try chunks([
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#),
            ("message_stop", "{}"),
        ])
        #expect(result.last == .done(finishReason: "end_turn"))
    }

    @Test("error 事件抛服务端错误")
    func errorEvent() {
        #expect(throws: ChatError.self) {
            var mapper = AnthropicChunkMapper()
            _ = try mapper.map(SSEEvent(event: "error",
                                        data: #"{"error":{"type":"overloaded_error","message":"服务繁忙"}}"#,
                                        id: nil, retry: nil))
        }
    }

    @Test("ping 事件被忽略")
    func pingIgnored() throws {
        #expect(try chunks([("ping", "{}")]).isEmpty)
    }

    @Test("完整流：思考块 + 正文块 + 用量 + 结束")
    func fullStream() throws {
        let result = try chunks([
            ("message_start", #"{"message":{"usage":{"input_tokens":10,"output_tokens":0}}}"#),
            ("content_block_start", #"{"index":0,"content_block":{"type":"thinking"}}"#),
            ("content_block_delta", #"{"index":0,"delta":{"type":"thinking_delta","thinking":"嗯"}}"#),
            ("content_block_stop", #"{"index":0}"#),
            ("content_block_start", #"{"index":1,"content_block":{"type":"text"}}"#),
            ("content_block_delta", #"{"index":1,"delta":{"type":"text_delta","text":"答案"}}"#),
            ("content_block_stop", #"{"index":1}"#),
            ("message_delta", #"{"delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":42}}"#),
            ("message_stop", "{}"),
        ])
        #expect(result == [
            .reasoningDelta("嗯"),
            .textDelta("答案"),
            .usage(TokenUsage(prompt: 10, completion: 42)),
            .done(finishReason: "end_turn"),
        ])
    }

    @Test("请求构造：x-api-key、版本头与顶层 system 字段")
    func buildRequest() throws {
        let adapter = AnthropicAdapter()
        let config = ProviderConfig(kind: .anthropic,
                                    baseURL: URL(string: "https://api.anthropic.com")!,
                                    apiKey: "sk-ant-test",
                                    model: "claude-sonnet-5")
        let request = ChatRequest(model: "claude-sonnet-5",
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: "你是助手",
                                  temperature: 0.7,
                                  maxTokens: 2048)
        let urlRequest = try adapter.buildRequest(request, config: config)

        #expect(urlRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "sk-ant-test")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == nil)

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        // system 是顶层字段，不在 messages 里
        #expect(json["system"] as? String == "你是助手")
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
    }
}
