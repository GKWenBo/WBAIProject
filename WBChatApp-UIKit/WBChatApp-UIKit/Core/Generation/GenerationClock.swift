import Foundation

/// 生成协调器用的时钟（快照间隔、后台时限），测试里可注入立即返回的实现
protocol GenerationClock: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct SystemGenerationClock: GenerationClock {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// 后台执行时间的抽象，隔离 UIApplication，便于测试
@MainActor
protocol BackgroundExecution: AnyObject {
    /// 申请后台时间，返回是否申请成功；系统回收前调用 expiration
    func begin(expiration: @escaping @MainActor () -> Void) -> Bool
    func end()
}
