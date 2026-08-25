import UIKit

/// 思考过程折叠区。默认折叠，点标题展开。
final class ReasoningSectionView: UIView {

    private static let headerHeight: CGFloat = 28

    private let headerButton: UIButton = {
        let button = UIButton(type: .system)
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.setTitleColor(Theme.textSecondary, for: .normal)
        return button
    }()

    private let bodyLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = Theme.textSecondary
        return label
    }()

    private var isExpanded = false
    private var text: String = ""

    var onToggle: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(headerButton)
        addSubview(bodyLabel)
        headerButton.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        updateHeaderTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func setText(_ newText: String) {
        text = newText
        bodyLabel.text = newText
        bodyLabel.isHidden = !isExpanded
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        guard isExpanded else { return Self.headerHeight }
        let bodyHeight = bodyLabel.sizeThatFits(CGSize(width: width,
                                                       height: .greatestFiniteMagnitude)).height
        return Self.headerHeight + ceil(bodyHeight) + 4
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headerButton.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.headerHeight)
        if isExpanded {
            let height = bodyLabel.sizeThatFits(CGSize(width: bounds.width,
                                                       height: .greatestFiniteMagnitude)).height
            bodyLabel.frame = CGRect(x: 0, y: Self.headerHeight + 4,
                                     width: bounds.width, height: ceil(height))
        } else {
            bodyLabel.frame = .zero
        }
    }

    @objc private func toggle() {
        isExpanded.toggle()
        bodyLabel.isHidden = !isExpanded
        updateHeaderTitle()
        setNeedsLayout()
        onToggle?()
    }

    private func updateHeaderTitle() {
        headerButton.setTitle(isExpanded ? "▾ 思考过程" : "▸ 思考过程", for: .normal)
    }
}
