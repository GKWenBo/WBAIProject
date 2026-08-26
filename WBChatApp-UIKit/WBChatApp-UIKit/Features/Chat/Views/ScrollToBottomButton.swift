import UIKit

/// 脱离贴底时浮出的「回到底部」圆钮。
final class ScrollToBottomButton: UIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)
        setImage(UIImage(systemName: "arrow.down"), for: .normal)
        tintColor = Theme.textPrimary
        backgroundColor = Theme.secondaryBackground
        layer.cornerRadius = 18
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        accessibilityIdentifier = "chat.scrollToBottom"
        alpha = 0
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func setVisible(_ visible: Bool) {
        UIView.animate(withDuration: 0.2) { self.alpha = visible ? 1 : 0 }
    }
}
