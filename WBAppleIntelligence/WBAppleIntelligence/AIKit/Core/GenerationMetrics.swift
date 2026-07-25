import Foundation

// 显式 nonisolated：工程默认把没有标注的类型/扩展成员推断为 @MainActor，
// 但这里是给耗时采样用的纯计算，需要能在 MetricsTimer 等非隔离上下文里同步调用，
// 所以主动退出默认隔离（扩展不会继承类型声明处的 nonisolated，需单独标注）。
nonisolated extension Duration {
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
///
/// 显式 `nonisolated`：AIKit/Core 是纯逻辑层，这个值类型要能在生成流程的任意
/// 隔离域（含非隔离的后台任务）里被采样、传递和比较，不应被工程默认的
/// `@MainActor` 隔离绑住，即便它已经是 `Sendable`——`Sendable` 只保证跨域传递
/// 安全，不等于退出了默认隔离推断。
nonisolated struct GenerationMetrics: Equatable, Sendable {
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
///
/// 显式 `nonisolated`：采样发生在流式生成的回调链路上，调用方不一定在主线程，
/// 同样要退出工程默认的 `@MainActor` 隔离。
nonisolated struct MetricsTimer {
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
