import Foundation

extension Duration {
    /// 转成以秒为单位的浮点值。
    ///
    /// `components` 拆出的是秒与阿托秒（1e-18 秒）两段整数，直接相加才能保住亚毫秒精度；
    /// 只取 `components.seconds` 会把 200 毫秒的首字延迟四舍五入成 0。
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}

/// 单次生成的性能指标。
///
/// 端侧推理的说服力集中在这几个数字上：首字延迟决定体感，token 速率决定长文本的等待时间，
/// token 数决定会不会撞上 4096 的上下文窗口。所以每个 Demo 都把它们显式展示出来。
struct GenerationMetrics: Equatable, Sendable {
    /// 从发起请求到收到第一个增量的耗时（秒）。非流式调用没有这个值。
    var firstTokenLatency: TimeInterval?
    /// 整次生成的总耗时（秒）。
    var totalDuration: TimeInterval?
    var promptTokenCount: Int?
    var responseTokenCount: Int?

    static let empty = GenerationMetrics()

    /// 输出速率。缺少任一输入时返回 nil 而不是 0——0 会被误读成「卡住了」。
    var tokensPerSecond: Double? {
        guard let responseTokenCount,
              let totalDuration,
              totalDuration > 0
        else { return nil }
        return Double(responseTokenCount) / totalDuration
    }
}

/// 生成过程的耗时采样器。
///
/// 用 `ContinuousClock` 而不是 `Date`：前者是单调时钟，不会因为用户改系统时间或
/// 系统对时而出现负数耗时。
struct MetricsTimer {
    private let start = ContinuousClock.now
    private var firstTokenAt: ContinuousClock.Instant?

    /// 标记收到首个增量。重复调用只有第一次生效。
    mutating func markFirstToken() {
        guard firstTokenAt == nil else { return }
        firstTokenAt = ContinuousClock.now
    }

    func finish(promptTokenCount: Int?, responseTokenCount: Int?) -> GenerationMetrics {
        GenerationMetrics(
            firstTokenLatency: firstTokenAt.map { ($0 - start).seconds },
            totalDuration: (ContinuousClock.now - start).seconds,
            promptTokenCount: promptTokenCount,
            responseTokenCount: responseTokenCount
        )
    }
}
