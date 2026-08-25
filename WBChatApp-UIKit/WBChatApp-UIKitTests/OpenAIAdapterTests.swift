import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("OpenAI 兼容协议适配")
struct OpenAIAdapterTests {

    private func chunks(_ payloads: [String]) throws -> [StreamChunk] {
        var mapper = OpenAIChunkMapper()
        var result: [StreamChunk] = []
        for payload in payloads {
            result += try mapper.map(SSEEvent(event: nil, data: payload, id: nil, retry: nil))
        }
        return result
    }

    @Test("正文增量")
    func textDelta() throws {
        let result = try chunks([#"{"choices":[{"delta":{"content":"你好"}}]}"#])
        #expect(result == [.textDelta("你好")])
    }

    @Test("思考增量走 reasoning_content")
    func reasoningDelta() throws {
        let result = try chunks([#"{"choices":[{"delta":{"reasoning_content":"先想想"}}]}"#])
        #expect(result == [.reasoningDelta("先想想")])
    }

    @Test("同一帧里正文与思考都存在时按思考在前输出")
    func bothDeltas() throws {
        let result = try chunks([#"{"choices":[{"delta":{"reasoning_content":"A","content":"B"}}]}"#])
        #expect(result == [.reasoningDelta("A"), .textDelta("B")])
    }

    @Test("空 delta 不产生任何事件")
    func emptyDelta() throws {
        #expect(try chunks([#"{"choices":[{"delta":{}}]}"#]).isEmpty)
    }

    @Test("[DONE] 标记结束")
    func doneMarker() throws {
        #expect(try chunks(["[DONE]"]) == [.done(finishReason: nil)])
    }

    @Test("finish_reason 被带出")
    func finishReason() throws {
        let result = try chunks([#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#])
        #expect(result == [.done(finishReason: "stop")])
    }

    @Test("末帧 usage 被映射")
    func usage() throws {
        let result = try chunks([#"{"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":34}}"#])
        #expect(result == [.usage(TokenUsage(prompt: 12, completion: 34))])
    }

    @Test("完整流：多帧增量 + usage + DONE")
    func fullStream() throws {
        let result = try chunks([
            #"{"choices":[{"delta":{"content":"Hel"}}]}"#,
            #"{"choices":[{"delta":{"content":"lo"}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":2}}"#,
            "[DONE]",
        ])
        #expect(result == [
            .textDelta("Hel"),
            .textDelta("lo"),
            .usage(TokenUsage(prompt: 1, completion: 2)),
            .done(finishReason: "stop"),
            .done(finishReason: nil),
        ])
    }

    @Test("非法 JSON 抛解码错误")
    func invalidJSON() {
        #expect(throws: ChatError.self) {
            var mapper = OpenAIChunkMapper()
            _ = try mapper.map(SSEEvent(event: nil, data: "{ 坏掉的", id: nil, retry: nil))
        }
    }

    @Test("请求构造：URL、鉴权头、stream 开关与 system 并入 messages")
    func buildRequest() throws {
        let adapter = OpenAICompatibleAdapter()
        let config = ProviderConfig(kind: .deepSeek,
                                    baseURL: URL(string: "https://api.deepseek.com")!,
                                    apiKey: "sk-test",
                                    model: "deepseek-chat")
        let request = ChatRequest(model: "deepseek-chat",
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: "你是助手",
                                  temperature: 0.7,
                                  maxTokens: 2048)
        let urlRequest = try adapter.buildRequest(request, config: config)

        #expect(urlRequest.url?.absoluteString == "https://api.deepseek.com/v1/chat/completions")
        #expect(urlRequest.httpMethod == "POST")
        #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(urlRequest.value(forHTTPHeaderField: "Accept") == "text/event-stream")

        let body = try #require(urlRequest.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "你是助手")
        #expect(messages[1]["role"] as? String == "user")
    }
}
