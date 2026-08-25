import QuartzCore

/// 把高频的网络增量合并到屏幕刷新节奏上。
/// 抽成协议是为了让 ViewModel 能在测试里被手动驱动。
protocol StreamThrottling: AnyObject {
    var onTick: (() -> Void)? { get set }
    func start()
    func stop()
}

/// 生产实现：CADisplayLink 天然与屏幕刷新率对齐（60/120Hz），
/// 保证每帧最多一次排版、最多一次贴底滚动。
final class DisplayLinkThrottle: StreamThrottling {

    var onTick: (() -> Void)?

    private var displayLink: CADisplayLink?

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(handleTick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleTick() {
        onTick?()
    }

    deinit {
        displayLink?.invalidate()
    }
}
