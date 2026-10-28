import UIKit

/// 助手消息正文下方的常驻操作栏：左侧「复制」，右侧「重新生成」或「重试保存」。
///
/// 高度恒定为 `height`，按钮显隐不影响占位——流式开始/结束时只切换按钮，
/// 行高保持不变，避免点「重新生成」后整屏内容上下跳一下。
final class MessageActionBar: UIView {

    static let height: CGFloat = 40

    enum Trailing: Equatable {
        case none
        case regenerate
        /// 落库失败时的恢复入口，语义与重新生成不同，用文字按钮区分
        case retrySave
    }

    var onCopy: (() -> Void)?
    var onTrailing: (() -> Void)?

    private static let buttonSize: CGFloat = 36

    private let copyButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        button.tintColor = Theme.textSecondary
        button.accessibilityIdentifier = "message.copy"
        button.accessibilityLabel = "复制"
        return button
    }()

    private let regenerateButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.clockwise"), for: .normal)
        button.tintColor = Theme.textSecondary
        button.accessibilityIdentifier = "message.regenerate"
        button.accessibilityLabel = "重新生成"
        return button
    }()

    private let retrySaveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重试保存", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.accessibilityIdentifier = "message.retrySave"
        return button
    }()

    /// 复制成功后图标短暂切成对勾，到点再换回来
    private var copyFeedbackWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        for button in [copyButton, regenerateButton, retrySaveButton] {
            addSubview(button)
        }
        copyButton.addTarget(self, action: #selector(handleCopy), for: .touchUpInside)
        regenerateButton.addTarget(self, action: #selector(handleTrailing), for: .touchUpInside)
        retrySaveButton.addTarget(self, action: #selector(handleTrailing), for: .touchUpInside)
        configure(canCopy: false, trailing: .none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(canCopy: Bool, trailing: Trailing) {
        copyButton.isHidden = !canCopy
        regenerateButton.isHidden = trailing != .regenerate
        retrySaveButton.isHidden = trailing != .retrySave
    }

    /// 复用或重新生成前复位：隐藏按钮、取消复制反馈、清空回调
    func reset() {
        configure(canCopy: false, trailing: .none)
        copyFeedbackWorkItem?.cancel()
        copyFeedbackWorkItem = nil
        copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        onCopy = nil
        onTrailing = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = Self.buttonSize
        let y = (bounds.height - size) / 2
        // 图标按钮内容居中，向左偏移半个留白让图标与正文左边缘对齐
        let iconInset = (size - 22) / 2
        copyButton.frame = CGRect(x: -iconInset, y: y, width: size, height: size)
        regenerateButton.frame = CGRect(x: bounds.width - size + iconInset, y: y,
                                        width: size, height: size)
        let titleWidth = retrySaveButton.intrinsicContentSize.width
        retrySaveButton.frame = CGRect(x: bounds.width - titleWidth, y: y,
                                       width: titleWidth, height: size)
    }

    @objc private func handleCopy() {
        onCopy?()
        copyButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        copyFeedbackWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.copyButton.setImage(UIImage(systemName: "doc.on.doc"), for: .normal)
        }
        copyFeedbackWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
    }

    @objc private func handleTrailing() {
        onTrailing?()
    }
}
