import Foundation

/// 唯一的网络实现。协议差异全部由注入的 adapter 承担，
/// 因此新增一家服务商不需要改这里。
final class NetworkChatProvider: ChatProvider {

    private let adapter: ProviderAdapter
    private let config: ProviderConfig
    private let session: URLSession
    private let timing: StreamTimingConfiguration
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

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try adapter.buildRequest(request, config: config)
                    let progress = SemanticStreamProgress(clock: self.clock)
                    try await withThrowingTaskGroup(of: Void.self) { group in
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

                            switch await progress.endOfTransport() {
                            case .alreadyTerminated:
                                return
                            case .finishReason(let reason):
                                continuation.yield(.done(finishReason: reason))
                            case .interrupted:
                                throw ChatError.interruptedStream
                            }
                        }

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

actor SemanticStreamProgress {
    struct TerminalClaim {
        let reason: String?
    }

    enum EndOfTransport {
        case alreadyTerminated
        case finishReason(String)
        case interrupted
    }

    enum MonitorResult {
        case keepWaiting
        case finished
        case finishTail(String)
        case timedOut
    }

    private let clock: any StreamClock
    private var lastProgressAt: ContinuousClock.Instant

    init(clock: any StreamClock) {
        self.clock = clock
        lastProgressAt = clock.now
    }
    private var pendingFinishReason: (reason: String, receivedAt: ContinuousClock.Instant)?
    private var terminated = false
    private(set) var hasCompletedSuccessfully = false
    var isTerminated: Bool { terminated }

    func receivedSemanticProgress() {
        lastProgressAt = clock.now
    }

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
