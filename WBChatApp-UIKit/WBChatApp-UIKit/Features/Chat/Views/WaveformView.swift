import UIKit

/// 简易柱状波形。新音量从右侧推入，整体左移。
final class WaveformView: UIView {

    private var levels: [Float] = []
    private let barCount = 32
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        levels = Array(repeating: 0, count: barCount)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func update(level: Float) {
        levels.removeFirst()
        levels.append(max(0.05, min(1, level)))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(Theme.accent.cgColor)

        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        var x = (rect.width - totalWidth) / 2

        for level in levels {
            let height = max(2, rect.height * CGFloat(level))
            let barRect = CGRect(x: x, y: (rect.height - height) / 2,
                                 width: barWidth, height: height)
            context.addPath(UIBezierPath(roundedRect: barRect,
                                         cornerRadius: barWidth / 2).cgPath)
            context.fillPath()
            x += barWidth + barSpacing
        }
    }
}
