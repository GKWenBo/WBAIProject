import UIKit

/// 段落 / 标题 / 列表 / 引用 / 表格的承载视图。
///
/// 内部是一个非编辑态的 `UITextView`，在 iOS 16+ 默认由 **TextKit 2** 驱动。
///
/// ⚠️ 全类禁止访问 `textView.layoutManager` 与 `textView.textStorage`——
/// 只要碰一次，UIKit 就会静默回退到 TextKit 1，增量排版的收益全部作废。
/// 需要底层能力时一律走 `textLayoutManager` / `textContentStorage`。
final class MarkdownTextBlockView: UIView, BlockView {

    static let viewKind: BlockViewKind = .text

    var onLinkTap: ((URL) -> Void)?

    private let textView: UITextView = {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    /// 引用块左侧竖条
    private let quoteBar: UIView = {
        let view = UIView()
        view.backgroundColor = Theme.separator
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var leadingConstraint: NSLayoutConstraint!

    /// 供测试断言：确认没有意外退回 TextKit 1
    var usesTextKit2: Bool { textView.textLayoutManager != nil }

    /// 供测试断言当前内容
    var currentTextForTesting: String { textView.attributedText?.string ?? "" }

    /// 供测试断言：引用块竖条是否隐藏、缩进常量的当前值
    var quoteBarHiddenForTesting: Bool { quoteBar.isHidden }
    var leadingConstantForTesting: CGFloat { leadingConstraint.constant }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    private func setUp() {
        addSubview(quoteBar)
        addSubview(textView)

        leadingConstraint = textView.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            quoteBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            quoteBar.topAnchor.constraint(equalTo: topAnchor),
            quoteBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            quoteBar.widthAnchor.constraint(equalToConstant: MarkdownTheme.default.quoteBarWidth),

            leadingConstraint,
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        textView.addGestureRecognizer(tap)
    }

    // MARK: - BlockView

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer) {
        textView.attributedText = attributed

        let isQuote = block.kind == .blockQuote
        quoteBar.isHidden = !isQuote
        leadingConstraint.constant = isQuote ? MarkdownTheme.default.quoteBarWidth + 8 : 0
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let inset = quoteBar.isHidden ? 0 : MarkdownTheme.default.quoteBarWidth + 8
        let available = max(1, width - inset)
        let size = textView.sizeThatFits(CGSize(width: available,
                                                height: .greatestFiniteMagnitude))
        return ceil(size.height)
    }

    func prepareForReuse() {
        textView.attributedText = NSAttributedString()
        quoteBar.isHidden = true
        leadingConstraint.constant = 0
        onLinkTap = nil
    }

    // MARK: - 链接点击

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handleTap(at: gesture.location(in: textView))
    }

    /// `closestPosition(to:)` 只返回「离点击点最近的文本位置」，不校验点击点
    /// 是否真的落在该字符的 glyph 包围盒内——文本末尾之后、行间空白、短行右侧
    /// 空白处点击，仍可能命中最近字符所在的链接范围。这里额外用
    /// `firstRect(for:)` 取该字符的实际矩形，校验点击点确实落在里面才触发回调。
    private func handleTap(at point: CGPoint) {
        guard let onLinkTap else { return }
        guard let position = textView.closestPosition(to: point) else { return }

        // 取「最近位置」往后一个字符的范围；若已在文末（往后取不到字符），
        // 退而取往前一个字符的范围。两者都取不到（空文档）就没有可命中的字符。
        let range: UITextRange?
        if let forward = textView.position(from: position, offset: 1) {
            range = textView.textRange(from: position, to: forward)
        } else if let backward = textView.position(from: position, offset: -1) {
            range = textView.textRange(from: backward, to: position)
        } else {
            range = nil
        }
        guard let range else { return }
        let rect = textView.firstRect(for: range)
        guard !rect.isNull, rect.contains(point) else { return }

        let index = textView.offset(from: textView.beginningOfDocument, to: position)
        guard index >= 0, index < (textView.attributedText?.length ?? 0) else { return }
        guard let url = textView.attributedText?
            .attribute(.wbLinkURL, at: index, effectiveRange: nil) as? URL else { return }
        onLinkTap(url)
    }

    /// 供测试模拟点击：`UITapGestureRecognizer` 在单测里不便直接触发
    func simulateTapForTesting(at point: CGPoint) {
        handleTap(at: point)
    }
}
