import Foundation
import Testing
@testable import WBAppleIntelligence

struct GenerationMetricsTests {

    @Test("Duration 转秒：1.5 秒")
    func durationToSeconds() {
        let duration = Duration.milliseconds(1500)
        #expect(abs(duration.seconds - 1.5) < 0.000_001)
    }

    @Test("Duration 转秒：亚毫秒精度不被丢弃")
    func durationKeepsSubMillisecondPrecision() {
        let duration = Duration.microseconds(250)
        #expect(abs(duration.seconds - 0.000_25) < 0.000_000_1)
    }

    @Test("每秒 token 数按输出 token 与总耗时计算")
    func tokensPerSecond() {
        let metrics = GenerationMetrics(
            firstTokenLatency: 0.2,
            totalDuration: 4,
            promptTokenCount: 30,
            responseTokenCount: 120
        )
        #expect(metrics.tokensPerSecond == 30)
    }

    @Test("缺少输出 token 数时不给出速率，而不是给 0 误导人")
    func tokensPerSecondNeedsResponseCount() {
        let metrics = GenerationMetrics(totalDuration: 4)
        #expect(metrics.tokensPerSecond == nil)
    }

    @Test("总耗时为零时不做除法")
    func tokensPerSecondGuardsZeroDuration() {
        let metrics = GenerationMetrics(totalDuration: 0, responseTokenCount: 120)
        #expect(metrics.tokensPerSecond == nil)
    }

    @Test("采样器未标记首个增量时不给出首字延迟")
    func timerWithoutFirstToken() {
        let timer = MetricsTimer()
        let metrics = timer.finish(promptTokenCount: nil, responseTokenCount: nil)
        #expect(metrics.firstTokenLatency == nil)
        #expect(metrics.totalDuration != nil)
    }

    @Test("采样器只记录第一次标记，后续标记不覆盖")
    func timerKeepsFirstMark() async throws {
        var timer = MetricsTimer()
        timer.markFirstToken()
        let first = timer.finish(promptTokenCount: nil, responseTokenCount: nil).firstTokenLatency
        try await Task.sleep(for: .milliseconds(20))
        timer.markFirstToken()
        let second = timer.finish(promptTokenCount: nil, responseTokenCount: nil).firstTokenLatency
        #expect(first == second)
    }
}
