import Foundation
import Network
import Testing
@testable import WBChatApp_UIKit

/// 真正经过 TCP / URLSession 的本地 SSE 服务，无 URLProtocol 拦截。
private final class LocalSSEServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.local-sse")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var disconnected = false
    var clientDisconnected: Bool { lock.withLock { disconnected } }

    init() throws { listener = try NWListener(using: .tcp, on: .any) }

    func start(body: String, close: Bool) async throws -> URL {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.withLock { self.connections.append(connection) }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                let header = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n"
                // 单字节 write 确保包括 UTF-8、CRLF 在内的分片经过真实传输入口。
                let payload = Array((header + body).utf8)
                self.send(payload, index: 0, connection: connection, close: close)
                self.watchDisconnect(connection)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(returning: URL(string: "http://127.0.0.1:\(self.listener.port!.rawValue)")!)
                case .failed(let error):
                    self.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
    }

    private func send(_ bytes: [UInt8], index: Int, connection: NWConnection, close: Bool) {
        guard index < bytes.count else {
            if close { connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in }) }
            return
        }
        connection.send(content: Data([bytes[index]]), completion: .contentProcessed { [weak self] error in
            guard error == nil else { return }
            self?.send(bytes, index: index + 1, connection: connection, close: close)
        })
    }

    private func watchDisconnect(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, complete, error in
            guard let self else { return }
            if complete || error != nil {
                self.lock.withLock { self.disconnected = true }
            } else { self.watchDisconnect(connection) }
        }
    }

    func sendBody(_ body: String) {
        let connection = lock.withLock { connections.first }
        connection?.send(content: Data(body.utf8), completion: .contentProcessed { _ in })
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() }; connections.removeAll() }
    }
}

private final class AdjustableStreamClock: StreamClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now
    var now: ContinuousClock.Instant { lock.withLock { instant } }
    func advance(_ duration: Duration) { lock.withLock { instant = instant.advanced(by: duration) } }
    func sleep(for duration: Duration) async throws {
        let deadline = now.advanced(by: duration)
        while now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        try Task.checkCancellation()
    }
}

@Suite("真实 SSE 传输入口", .serialized)
struct StreamTransportIntegrationTests {
    private let request = ChatRequest(model: "m", messages: [ChatMessage(role: .user, content: "hi")],
                                      system: nil, temperature: 0.7, maxTokens: 128)
    private func provider(_ url: URL, clock: any StreamClock = SystemStreamClock(),
                          timing: StreamTimingConfiguration = .default) -> NetworkChatProvider {
        NetworkChatProvider(config: ProviderConfig(kind: .openAI, baseURL: url, apiKey: "test", model: "m"),
                            session: URLSession(configuration: .ephemeral), timing: timing, clock: clock)
    }

    @Test("真实 TCP UTF-8 / CRLF 分片与协议结束后关闭底层请求")
    func fragmentedTCPAndDone() async throws {
        let server = try LocalSSEServer()
        defer { server.stop() }
        let url = try await server.start(body: "data: {\"choices\":[{\"delta\":{\"content\":\"你好🌍\"}}]}\r\n\r\ndata: [DONE]\r\n\r\n", close: false)
        var chunks: [StreamChunk] = []
        for try await chunk in provider(url).stream(request) { chunks.append(chunk) }
        #expect(chunks == [.textDelta("你好🌍"), .done(finishReason: nil)])
        for _ in 0..<100 where !server.clientDisconnected { try await Task.sleep(for: .milliseconds(10)) }
        #expect(server.clientDisconnected)
    }

    @Test("真实 TCP 异常 EOF 保留已收到增量并报中断")
    func truncatedTCP() async throws {
        let server = try LocalSSEServer()
        defer { server.stop() }
        let url = try await server.start(body: "data: {\"choices\":[{\"delta\":{\"content\":\"半截\"}}]}\n\n", close: true)
        var chunks: [StreamChunk] = []
        do {
            for try await chunk in provider(url).stream(request) { chunks.append(chunk) }
            Issue.record("缺少终止标记必须失败")
        } catch { #expect(error as? ChatError == .interruptedStream) }
        #expect(chunks == [.textDelta("半截")])
    }

    @Test("可注入时钟推进180秒，usage不是正文或思考进展")
    func injectedSemanticTimeout() async throws {
        let server = try LocalSSEServer()
        defer { server.stop() }
        let url = try await server.start(body: "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2}}\n\n", close: false)
        let clock = AdjustableStreamClock()
        var timing = StreamTimingConfiguration.default
        timing.networkIdleTimeout = .seconds(300)
        let started = clock.now
        let watchdog = Task {
            try await Task.sleep(for: .seconds(1))
            clock.advance(.seconds(600))
        }
        defer { watchdog.cancel() }
        var usageCount = 0
        do {
            for try await chunk in provider(url, clock: clock, timing: timing).stream(request) {
                if case .usage = chunk {
                    usageCount += 1
                    if usageCount == 1 {
                        clock.advance(.seconds(179))
                        server.sendBody("data: {\"choices\":[],\"usage\":{\"prompt_tokens\":2,\"completion_tokens\":3}}\n\n")
                    } else { clock.advance(.seconds(2)) }
                }
            }
            Issue.record("无语义进展必须超时")
        } catch { #expect(error as? ChatError == .timeout) }
        #expect(usageCount == 2)
        #expect(clock.now - started == .seconds(181))
    }

    @Test("真实 TCP finish_reason 后服务器不关闭，尾部时间到达自动收尾")
    func boundedTailTCP() async throws {
        let server = try LocalSSEServer()
        defer { server.stop() }
        let url = try await server.start(body: "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"length\"}]}\n\n", close: false)
        var timing = StreamTimingConfiguration.default
        timing.usageTailTimeout = .milliseconds(50)
        timing.pollingInterval = .milliseconds(5)
        var chunks: [StreamChunk] = []
        for try await chunk in provider(url, timing: timing).stream(request) { chunks.append(chunk) }
        #expect(chunks == [.done(finishReason: "length")])
        for _ in 0..<100 where !server.clientDisconnected { try await Task.sleep(for: .milliseconds(10)) }
        #expect(server.clientDisconnected)
    }
}
