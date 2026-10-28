import Foundation

/// 唯一的网络实现。协议差异全部由注入的 adapter 承担，
/// 因此新增一家服务商不需要改这里。
final class NetworkChatProvider: ChatProvider {

    private let adapter: ProviderAdapter
    private let config: ProviderConfig
    private let session: URLSession
    /// 各类超时阈值
    private let timing: StreamTimingConfiguration
    /// 可注入的时钟，测试里用来快进时间
    private let clock: any StreamClock

    init(adapter: ProviderAdapter,
         config: ProviderConfig,
         session: URLSession = .shared,
         timing: StreamTimingConfiguration = .default,
         clock: any StreamClock = SystemStreamClock()) {
        self.adapter = adapter
        self.config = config
        self.session = session
        self.timing = timing
        self.clock = clock
    }

    /// 按当前服务商种类挑选 adapter 的便利构造
    convenience init(config: ProviderConfig,
                     session: URLSession = .shared,
                     timing: StreamTimingConfiguration = .default,
                     clock: any StreamClock = SystemStreamClock()) {
        let adapter: ProviderAdapter = config.kind.usesAnthropicProtocol
            ? AnthropicAdapter()
            : OpenAICompatibleAdapter()
        self.init(adapter: adapter, config: config, session: session, timing: timing, clock: clock)
    }

    /// 两个子任务竞速，先结束的一方决定结果：
    /// - reader：读 SSE、映射成统一事件、转发给上层；
    /// - monitor：定时检查"语义无进展超时"与"拿到停止原因后等待尾部 usage 超时"。
    /// 由 `SemanticStreamProgress` 保证只有一方能宣告终止。
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try adapter.buildRequest(request, config: config)
                    let progress = SemanticStreamProgress(clock: self.clock)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        // reader
                        group.addTask {
                            var mapper = self.adapter.makeMapper()
                            let connection = SSEStream.connection(for: urlRequest,
                                                                  session: self.session,
                                                                  timing: self.timing, clock: self.clock)
                            do {
                                try await withTaskCancellationHandler {
                                    for try await event in connection.events {
                                        try Task.checkCancellation()
                                        for chunk in try mapper.map(event) {
                                            switch chunk {
                                            case .finishReason(let reason):
                                                await progress.receivedFinishReason(reason)

                                            case .done(let markerReason):
                                                if let terminal = await progress.claimTerminal(markerReason: markerReason) {
                                                    continuation.yield(.done(finishReason: terminal.reason))
                                                }
                                                break

                                            case .textDelta(let text), .reasoningDelta(let text):
                                                if !text.isEmpty { await progress.receivedSemanticProgress() }
                                                continuation.yield(chunk)

                                            case .usage:
                                                continuation.yield(chunk)
                                            }
                                        }
                                        if await progress.isTerminated { break }
                                    }
                                } onCancel: {
                                    connection.producer.cancel()
                                }
                                await connection.close()
                            } catch {
                                await connection.close()
                                // 尾部计时器已经提交成功时，取消 reader 只是释放传输。
                                // 清理阶段的取消/网络错误不能把已确认的成功改写为失败。
                                if await progress.hasCompletedSuccessfully { return }
                                throw error
                            }

                            // 连接自然结束：有停止原因算成功，否则算中断
                            switch await progress.endOfTransport() {
                            case .alreadyTerminated:
                                return
                            case .finishReason(let reason):
                                continuation.yield(.done(finishReason: reason))
                            case .interrupted:
                                throw ChatError.interruptedStream
                            }
                        }

                        // monitor
                        group.addTask {
                            while !Task.isCancelled {
                                do {
                                    try await self.clock.sleep(for: self.timing.pollingInterval)
                                } catch is CancellationError {
                                    return
                                }
                                switch await progress.monitor(at: self.clock.now, timing: self.timing) {
                                case .keepWaiting:
                                    continue
                                case .finished:
                                    return
                                case .finishTail(let reason):
                                    continuation.yield(.done(finishReason: reason))
                                    return
                                case .timedOut:
                                    throw ChatError.timeout
                                }
                            }
                        }

                        // 任一子任务结束即取消另一个
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
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// 一次流式请求的终止状态机，reader 与 monitor 共享。
/// "语义进展"指收到正文/思考增量，心跳和空帧不算，用于识别"连接还活着但模型不吐字"。
actor SemanticStreamProgress {
    /// reader 收到协议结束标记后抢到的终止权
    struct TerminalClaim {
        let reason: String?
    }

    /// 连接自然结束时的判定
    enum EndOfTransport {
        case alreadyTerminated
        case finishReason(String)
        case interrupted
    }

    /// monitor 每次轮询的判定
    enum MonitorResult {
        case keepWaiting
        case finished
        /// 已有停止原因，尾部 usage 等不到了，直接成功收尾
        case finishTail(String)
        case timedOut
    }

    private let clock: any StreamClock
    /// 最近一次语义进展的时间
    private var lastProgressAt: ContinuousClock.Instant

    init(clock: any StreamClock) {
        self.clock = clock
        lastProgressAt = clock.now
    }
    /// 已收到但尚未提交的停止原因（只记第一个），等待尾部 usage / 结束标记
    private var pendingFinishReason: (reason: String, receivedAt: ContinuousClock.Instant)?
    /// 是否已有一方宣告终止
    private var terminated = false
    /// 已以成功状态终止；此后的清理错误不应改写结果
    private(set) var hasCompletedSuccessfully = false
    var isTerminated: Bool { terminated }

    func receivedSemanticProgress() {
        lastProgressAt = clock.now
    }

    /// 收到停止原因也算一次进展，并开始计算尾部等待时间
    func receivedFinishReason(_ reason: String) {
        let now = clock.now
        lastProgressAt = now
        if pendingFinishReason == nil { pendingFinishReason = (reason, now) }
    }

    /// 返回 nil 表示另一个并发路径已经完成终止。
    func claimTerminal(markerReason: String?) -> TerminalClaim? {
        guard !terminated else { return nil }
        terminated = true
        hasCompletedSuccessfully = true
        return TerminalClaim(reason: pendingFinishReason?.reason ?? markerReason)
    }

    func endOfTransport() -> EndOfTransport {
        guard !terminated else { return .alreadyTerminated }
        terminated = true
        if let reason = pendingFinishReason?.reason {
            hasCompletedSuccessfully = true
            return .finishReason(reason)
        }
        return .interrupted
    }

    /// 先判尾部等待超时（成功），再判语义无进展超时（失败）
    func monitor(at now: ContinuousClock.Instant,
                 timing: StreamTimingConfiguration) -> MonitorResult {
        if terminated { return .finished }
        if let pendingFinishReason,
           now - pendingFinishReason.receivedAt >= timing.usageTailTimeout {
            terminated = true
            hasCompletedSuccessfully = true
            return .finishTail(pendingFinishReason.reason)
        }
        if now - lastProgressAt >= timing.semanticProgressTimeout {
            terminated = true
            return .timedOut
        }
        return .keepWaiting
    }
}
