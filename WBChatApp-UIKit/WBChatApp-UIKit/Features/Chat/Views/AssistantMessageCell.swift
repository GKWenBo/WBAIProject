import UIKit

/// 助手消息 cell。左对齐、无气泡背景，贴合 ChatGPT 的排版。
final class AssistantMessageCell: UITableViewCell {

    static let reuseIdentifier = "AssistantMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 10

    private var stackView: BlockStackView?
    private var pool: BlockViewPool?

    private let reasoningView: ReasoningSectionView = {
        let view = ReasoningSectionView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let errorLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textColor = .systemRed
        label.numberOfLines = 0
        label.isHidden = true
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    var onLinkTap: ((URL) -> Void)?
    var onCodeCopy: ((String) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(reasoningView)
        contentView.addSubview(errorLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    func configure(blocks: [MarkdownBlock],
                   reasoning: String?,
                   status: MessageStatus,
                   errorText: String?,
                   pool: BlockViewPool,
                   cache: AttributedCache,
                   renderer: AttributedRenderer) {
        self.pool = pool

        let stack: BlockStackView
        if let existing = stackView {
            stack = existing
        } else {
            stack = BlockStackView(pool: pool, cache: cache, renderer: renderer)
            contentView.addSubview(stack)
            stackView = stack
        }
        stack.onLinkTap = { [weak self] in self?.onLinkTap?($0) }
        stack.onCodeCopy = { [weak self] in self?.onCodeCopy?($0) }
        stack.setBlocks(blocks)

        reasoningView.isHidden = (reasoning?.isEmpty ?? true)
        reasoningView.setText(reasoning ?? "")

        errorLabel.isHidden = (errorText?.isEmpty ?? true)
        errorLabel.text = errorText

        setNeedsLayout()
    }

    /// 流式增量：只把补丁转发给容器，不做任何全量重建
    func applyPatch(_ patch: BlockPatch) {
        stackView?.applyPatch(patch)
        setNeedsLayout()
    }

    func updateReasoning(_ text: String) {
        reasoningView.isHidden = text.isEmpty
        reasoningView.setText(text)
        setNeedsLayout()
    }

    func heightThatFits(width: CGFloat) -> CGFloat {
        let contentWidth = width - Self.horizontalInset * 2
        var height = Self.verticalInset * 2
        if !reasoningView.isHidden {
            height += reasoningView.heightThatFits(width: contentWidth) + 8
        }
        height += stackView?.heightThatFits(width: contentWidth) ?? 0
        if !errorLabel.isHidden {
            height += errorLabel.sizeThatFits(CGSize(width: contentWidth,
                                                     height: .greatestFiniteMagnitude)).height + 8
        }
        return ceil(height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let contentWidth = contentView.bounds.width - Self.horizontalInset * 2
        var y = Self.verticalInset

        if !reasoningView.isHidden {
            let height = reasoningView.heightThatFits(width: contentWidth)
            reasoningView.frame = CGRect(x: Self.horizontalInset, y: y,
                                         width: contentWidth, height: height)
            y += height + 8
        }
        if let stack = stackView {
            let height = stack.heightThatFits(width: contentWidth)
            stack.frame = CGRect(x: Self.horizontalInset, y: y,
                                 width: contentWidth, height: height)
            y += height
        }
        if !errorLabel.isHidden {
            let height = errorLabel.sizeThatFits(CGSize(width: contentWidth,
                                                        height: .greatestFiniteMagnitude)).height
            errorLabel.frame = CGRect(x: Self.horizontalInset, y: y + 8,
                                      width: contentWidth, height: height)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stackView?.recycleAll()
        reasoningView.isHidden = true
        errorLabel.isHidden = true
        onLinkTap = nil
        onCodeCopy = nil
    }
}
