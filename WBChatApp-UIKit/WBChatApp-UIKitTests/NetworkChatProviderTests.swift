import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 用 URLProtocol 拦截请求，按脚本回放报文。
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody: String = ""
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var headers: [String: String] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: Self.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite("网络传输层", .serialized)
struct NetworkChatProviderTests {

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func collect(_ provider: ChatProvider) async throws -> [StreamChunk] {
        let request = ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")],
                                  system: nil, temperature: 0.7, maxTokens: 128)
        var result: [StreamChunk] = []
        for try await chunk in provider.stream(request) { result.append(chunk) }
        return result
    }

    @Test("OpenAI 协议端到端")
    func openAIEndToEnd() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{"content":"你"}}]}

        data: {"choices":[{"delta":{"content":"好"}}]}

        data: [DONE]

        """
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .deepSeek, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        let chunks = try await collect(provider)
        #expect(chunks == [.textDelta("你"), .textDelta("好"), .done(finishReason: nil)])
    }

    @Test("Anthropic 协议端到端")
    func anthropicEndToEnd() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        event: content_block_delta
        data: {"delta":{"type":"text_delta","text":"嗨"}}

        event: message_stop
        data: {}

        """
        let provider = NetworkChatProvider(
            adapter: AnthropicAdapter(),
            config: ProviderConfig(kind: .anthropic, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        let chunks = try await collect(provider)
        #expect(chunks == [.textDelta("嗨"), .done(finishReason: nil)])
    }

    @Test("401 映射为 unauthorized")
    func unauthorized() async {
        StubURLProtocol.statusCode = 401
        StubURLProtocol.headers = [:]
        StubURLProtocol.responseBody = #"{"error":{"message":"bad key"}}"#
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.unauthorized) {
            _ = try await collect(provider)
        }
    }

    @Test("429 带出 Retry-After")
    func rateLimited() async {
        StubURLProtocol.statusCode = 429
        StubURLProtocol.headers = ["Retry-After": "30"]
        StubURLProtocol.responseBody = ""
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.rateLimited(retryAfter: 30)) {
            _ = try await collect(provider)
        }
    }

    @Test("缺少 API Key 直接抛错，不发请求")
    func missingKey() async {
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.missingAPIKey) {
            _ = try await collect(provider)
        }
    }

    @Test("MockProvider 逐块吐出脚本内容并以 done 收尾")
    func mockProvider() async throws {
        let provider = MockProvider(script: "abcdef", chunkSize: 2, delay: .zero)
        let chunks = try await collect(provider)
        let text = chunks.compactMap { if case .textDelta(let t) = $0 { return t } else { return nil } }
        #expect(text.joined() == "abcdef")
        #expect(chunks.last == .done(finishReason: "stop"))
    }
}
