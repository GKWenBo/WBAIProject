import UIKit

/// `BackgroundExecution` 的 UIKit 实现：进后台时申请一段后台时间，让正在生成的回复有机会落库。
@MainActor
final class UIKitBackgroundExecution: BackgroundExecution {
    /// 当前持有的后台任务，`.invalid` 表示没有
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    /// 申请后台时间，重复调用复用同一个任务；系统回收前先回调 expiration
    func begin(expiration: @escaping @MainActor () -> Void) -> Bool {
        guard identifier == .invalid else { return true }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "保存生成回复") { [weak self] in
            expiration()
            self?.end()
        }
        return identifier != .invalid
    }

    /// 结束后台任务，可重复调用
    func end() {
        guard identifier != .invalid else { return }
        let value = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(value)
    }
}
