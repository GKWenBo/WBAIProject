import Foundation

/// 流式请求的各类超时阈值
struct StreamTimingConfiguration: Sendable {
    /// 连续多久没收到任何字节判定为网络卡死
    var networkIdleTimeout: Duration
    /// 连续多久没收到正文/思考增量判定为模型无响应（心跳不算）
    var semanticProgressTimeout: Duration
    /// 单次请求的总时长上限
    var totalTimeout: Duration
    /// 收到停止原因后，最多再等多久尾部 usage / 结束标记
    var usageTailTimeout: Duration
    /// 超时检查的轮询间隔
    var pollingInterval: Duration

    static let `default` = StreamTimingConfiguration(
        networkIdleTimeout: .seconds(60),
        semanticProgressTimeout: .seconds(180),
        totalTimeout: .seconds(600),
        usageTailTimeout: .seconds(2),
        pollingInterval: .milliseconds(100)
    )
}

/// 时钟抽象，测试里注入可手动推进的实现
protocol StreamClock: Sendable {
    var now: ContinuousClock.Instant { get }
    func sleep(for duration: Duration) async throws
}

/// 生产环境使用的系统时钟
struct SystemStreamClock: StreamClock {
    var now: ContinuousClock.Instant { .now }
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// 记录字节到达时间，供超时监控任务跨线程读取（NSLock 保护）
private final class SSEStreamActivity: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: any StreamClock
    private let startedAt: ContinuousClock.Instant
    private var lastByteAt: ContinuousClock.Instant

    init(clock: any StreamClock) {
        self.clock = clock
        startedAt = clock.now
        lastByteAt = startedAt
    }

    func receivedByte() {
        lock.withLock {
            lastByteAt = clock.now
        }
    }

    func hasTimedOut(at now: ContinuousClock.Instant,
                     timing: StreamTimingConfiguration) -> Bool {
        lock.withLock {
            now - startedAt >= timing.totalTimeout ||
                now - lastByteAt >= timing.networkIdleTimeout
        }
    }
}

/// 一条 SSE 连接：事件流 + 背后的生产任务
struct SSEConnection: Sendable {
    let events: AsyncThrowingStream<SSEEvent, Error>
    /// 负责读字节与超时监控的任务，取消即断开连接
    let producer: Task<Void, Never>

    /// 取消并等待生产任务真正退出，确保 HTTP 连接已释放
    func close() async {
        producer.cancel()
        await producer.value
    }
}

/// 把一次 HTTP 请求变成 SSE 事件流。
/// 负责状态码检查与字节喂给解析器，不理解任何业务语义。
enum SSEStream {

    /// 建立连接：读字节任务与网络超时监控任务竞速，任一结束即取消另一个
    static func connection(for request: URLRequest,
                       session: URLSession,
                       timing: StreamTimingConfiguration = .default,
                       clock: any StreamClock = SystemStreamClock()) -> SSEConnection {
        var producer: Task<Void, Never>!
        let events = AsyncThrowingStream<SSEEvent, Error> { continuation in
            let task = Task {
                do {
                    let activity = SSEStreamActivity(clock: clock)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            let (bytes, response) = try await session.bytes(for: request)
                            // AsyncBytes 的迭代取消不保证释放仍打开的 HTTP 请求。
                            // 无论正常结束、协议提前结束还是超时，都显式取消实际任务。
                            defer { bytes.task.cancel() }
                            try await withTaskCancellationHandler {
                                try Task.checkCancellation()
                                try Self.validate(response)
                                let parser = SSEEventParser()
                                for try await byte in bytes {
                                    try Task.checkCancellation()
                                    activity.receivedByte()
                                    for event in parser.consume(byte: byte) {
                                        continuation.yield(event)
                                    }
                                }
                                for event in parser.finish() {
                                    continuation.yield(event)
                                }
                            } onCancel: {
                                bytes.task.cancel()
                            }
                        }

                        group.addTask {
                            while !Task.isCancelled {
                                do {
                                    try await clock.sleep(for: timing.pollingInterval)
                                } catch is CancellationError {
                                    return
                                }
                                if activity.hasTimedOut(at: clock.now, timing: timing) {
                                    throw ChatError.timeout
                                }
                            }
                        }

                        do {
                            _ = try await group.next()
                            group.cancelAll()
                            try await group.waitForAll()
                        } catch {
                            group.cancelAll()
                            throw error
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            producer = task
            continuation.onTermination = { _ in task.cancel() }
        }
        return SSEConnection(events: events, producer: producer)
    }

    /// 非 2xx 时直接根据状态码抛出对应的 `ChatError`。
    /// 注意：这里只读状态码与 `Retry-After` 头，**不读错误响应体**——
    /// `session.bytes(for:)` 返回的 `AsyncBytes` 是流式的，此处拿到的只是
    /// 首个响应头到达时的 `URLResponse`，body 还没被消费；`ChatError.serverError`
    /// 的 `message` 目前恒为 `nil`，服务端返回的错误文案不会被带给用户。
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        switch http.statusCode {
        case 401, 403:
            throw ChatError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ChatError.rateLimited(retryAfter: retryAfter)
        default:
            throw ChatError.serverError(status: http.statusCode, message: nil)
        }
    }
}
