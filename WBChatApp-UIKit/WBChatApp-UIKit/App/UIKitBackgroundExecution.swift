import UIKit

@MainActor
final class UIKitBackgroundExecution: BackgroundExecution {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    func begin(expiration: @escaping @MainActor () -> Void) -> Bool {
        guard identifier == .invalid else { return true }
        identifier = UIApplication.shared.beginBackgroundTask(withName: "保存生成回复") { [weak self] in
            expiration()
            self?.end()
        }
        return identifier != .invalid
    }
    func end() {
        guard identifier != .invalid else { return }
        let value = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(value)
    }
}
