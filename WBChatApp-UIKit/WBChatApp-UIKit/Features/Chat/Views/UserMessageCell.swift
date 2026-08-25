import UIKit

/// 用户消息 cell。右对齐气泡，**不做 Markdown 渲染**——
/// 用户输入的星号就该原样显示。
final class UserMessageCell: UITableViewCell {

    static let reuseIdentifier = "UserMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 6
    private static let bubblePadding = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    /// 气泡最宽占内容区的比例
    private static let maxWidthRatio: CGFloat = 0.78

    private let bubble: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.bubbleUser
        view.layer.cornerRadius = 18
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = Theme.textPrimary
        return label
    }()

    /// 供测试断言
    var displayedTextForTesting: String { label.text ?? "" }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(bubble)
        bubble.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(text: String) {
        label.text = text
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let size = labelSize(containerWidth: width)
        return ceil(size.height + Self.bubblePadding.top + Self.bubblePadding.bottom
                    + Self.verticalInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = labelSize(containerWidth: contentView.bounds.width)
        let bubbleWidth = size.width + Self.bubblePadding.left + Self.bubblePadding.right
        let bubbleHeight = size.height + Self.bubblePadding.top + Self.bubblePadding.bottom

        bubble.frame = CGRect(
            x: contentView.bounds.width - Self.horizontalInset - bubbleWidth,
            y: Self.verticalInset,
            width: bubbleWidth,
            height: bubbleHeight)
        label.frame = CGRect(x: Self.bubblePadding.left, y: Self.bubblePadding.top,
                             width: size.width, height: size.height)
    }

    private func labelSize(containerWidth: CGFloat) -> CGSize {
        let maxWidth = (containerWidth - Self.horizontalInset * 2) * Self.maxWidthRatio
            - Self.bubblePadding.left - Self.bubblePadding.right
        let fitted = label.sizeThatFits(CGSize(width: max(1, maxWidth),
                                               height: .greatestFiniteMagnitude))
        return CGSize(width: min(ceil(fitted.width), max(1, maxWidth)), height: ceil(fitted.height))
    }
}
