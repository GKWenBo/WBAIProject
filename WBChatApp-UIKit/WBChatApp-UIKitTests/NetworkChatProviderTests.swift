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

/// 发完响应头和可选首段 body 后保持连接，用于验证超时与取消是否真正传到 URLSession task。
final class HoldingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var stopLoadingCount = 0
    private static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!,
                                       statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !Self.responseBody.isEmpty {
            client?.urlProtocol(self, didLoad: Self.responseBody)
        }
    }

    override func stopLoading() {
        Self.lock.withLock {
            Self.stopLoadingCount += 1
        }
    }

    static func reset(body: String = "") {
        lock.withLock {
            responseBody = Data(body.utf8)
            stopLoadingCount = 0
        }
    }

    static var wasStopped: Bool {
        lock.withLock { stopLoadingCount > 0 }
    }
}

@Suite("网络传输层", .serialized)
struct NetworkChatProviderTests {

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeHoldingSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HoldingURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func shortTiming(networkIdle: Duration = .seconds(5),
                             semantic: Duration = .seconds(5),
                             total: Duration = .seconds(5),
                             usageTail: Duration = .milliseconds(50)) -> StreamTimingConfiguration {
        StreamTimingConfiguration(networkIdleTimeout: networkIdle,
                                  semanticProgressTimeout: semantic,
                                  totalTimeout: total,
                                  usageTailTimeout: usageTail,
                                  pollingInterval: .milliseconds(10))
    }

    private func expectTransportStopped() async {
        // URLSessionTask.cancel() 异步投递 URLProtocol.stopLoading()。
        // 等待该回调而非假定生产 Task 结束时回调已同步执行。
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !HoldingURLProtocol.wasStopped && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(HoldingURLProtocol.wasStopped)
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

    @Test("OpenAI 普通 EOF 缺少语义终止时判定为中断")
    func openAIEOFWithoutTerminalIsInterrupted() async {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{"content":"半截"}}]}

        """
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.interruptedStream) {
            _ = try await collect(provider)
        }
    }

    @Test("OpenAI finish_reason 后即使没有 DONE 也接受 EOF")
    func openAIFinishReasonThenEOFIsComplete() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{"content":"完整"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        """
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        #expect(try await collect(provider) == [
            .textDelta("完整"),
            .done(finishReason: "stop"),
        ])
    }

    @Test("OpenAI finish_reason 后仍收集独立 usage 尾帧")
    func openAICollectsUsageAfterFinishReason() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":5}}

        data: [DONE]

        """
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        #expect(try await collect(provider) == [
            .usage(TokenUsage(prompt: 3, completion: 5)),
            .done(finishReason: "stop"),
        ])
    }

    @Test("Anthropic 普通 EOF 缺少 message_stop 时判定为中断")
    func anthropicEOFWithoutMessageStopIsInterrupted() async {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.headers = ["Content-Type": "text/event-stream"]
        StubURLProtocol.responseBody = """
        event: content_block_delta
        data: {"delta":{"type":"text_delta","text":"半截"}}

        """
        let provider = NetworkChatProvider(
            adapter: AnthropicAdapter(),
            config: ProviderConfig(kind: .anthropic, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeSession())

        await #expect(throws: ChatError.interruptedStream) {
            _ = try await collect(provider)
        }
    }

    @Test("只使用 CR 分行的长连接无需等 EOF 即可完成")
    func crOnlyStreamCompletesBeforeEOF() async throws {
        HoldingURLProtocol.reset(body:
            "data: {\"choices\":[{\"delta\":{\"content\":\"你\"}}]}\r\rdata: [DONE]\r\r")
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming())

        #expect(try await collect(provider) == [.textDelta("你"), .done(finishReason: nil)])
        await expectTransportStopped()
    }

    @Test("finish_reason 后尾部长期不再到达时最多等待配置的 usage 窗口")
    func finishReasonTailHasBound() async throws {
        HoldingURLProtocol.reset(body:
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n")
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming(usageTail: .milliseconds(50)))

        let started = ContinuousClock.now
        #expect(try await collect(provider) == [.done(finishReason: "stop")])
        #expect(ContinuousClock.now - started < .seconds(1))
        await expectTransportStopped()
    }

    @Test("语义长期无进展映射为 timeout")
    func semanticProgressTimeout() async {
        HoldingURLProtocol.reset(body: ": keep-alive\n\n")
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming(semantic: .milliseconds(50)))

        await #expect(throws: ChatError.timeout) {
            _ = try await collect(provider)
        }
        await expectTransportStopped()
    }

    @Test("网络字节空闲超时映射为 timeout")
    func networkIdleTimeout() async {
        HoldingURLProtocol.reset()
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming(networkIdle: .milliseconds(50)))

        await #expect(throws: ChatError.timeout) {
            _ = try await collect(provider)
        }
        await expectTransportStopped()
    }

    @Test("总时长上限映射为 timeout")
    func totalTimeout() async {
        HoldingURLProtocol.reset(body: ": connected\n\n")
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming(total: .milliseconds(50)))

        await #expect(throws: ChatError.timeout) {
            _ = try await collect(provider)
        }
        await expectTransportStopped()
    }

    @Test("取消消费者会取消底层 URLSession 字节生产者")
    func cancellationReachesURLSessionProducer() async throws {
        HoldingURLProtocol.reset()
        let provider = NetworkChatProvider(
            adapter: OpenAICompatibleAdapter(),
            config: ProviderConfig(kind: .openAI, baseURL: URL(string: "https://x.test")!,
                                   apiKey: "k", model: "m"),
            session: makeHoldingSession(),
            timing: shortTiming())
        let request = ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")],
                                  system: nil, temperature: 0.7, maxTokens: 128)

        let consumer = Task {
            do {
                for try await _ in provider.stream(request) {}
            } catch {
                // 取消路径的错误对本测试无意义，只验证底层 producer 收到了 cancel。
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        consumer.cancel()
        _ = await consumer.result
        await expectTransportStopped()
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
