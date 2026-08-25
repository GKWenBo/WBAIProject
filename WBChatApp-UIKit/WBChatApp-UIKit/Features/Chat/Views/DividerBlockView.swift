import UIKit

/// 分割线。高度固定，与宽度无关。
final class DividerBlockView: UIView, BlockView {

    static let viewKind: BlockViewKind = .divider

    private static let totalHeight: CGFloat = 17
    private static let lineHeight: CGFloat = 1

    private let line: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(line)
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.centerYAnchor.constraint(equalTo: centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: Self.lineHeight),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {}

    func heightThatFits(width: CGFloat) -> CGFloat { Self.totalHeight }

    func prepareForReuse() {}
}
