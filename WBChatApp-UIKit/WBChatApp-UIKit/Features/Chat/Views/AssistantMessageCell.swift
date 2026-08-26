import UIKit

/// 助手消息 cell。左对齐、无气泡背景，贴合 ChatGPT 的排版。
final class AssistantMessageCell: UITableViewCell {

    static let reuseIdentifier = "AssistantMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 10

    private var stackView: BlockStackView?

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
    /// 生成失败或被用户停止时，点击「重新生成」按钮触发
    var onRetry: (() -> Void)?

    private lazy var retryButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("重新生成", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.accessibilityIdentifier = "message.retry"
        button.isHidden = true
        button.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)
        contentView.addSubview(button)
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(reasoningView)
        contentView.addSubview(errorLabel)
    }

    @objc private func handleRetry() {
        onRetry?()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    /// - Note: `pool` / `cache` / `renderer` 只在 cell 首次创建内部的 `BlockStackView`
    ///   时生效；cell 被复用（第二次及以后调用本方法）时会沿用首次捕获的那几个实例，
    ///   本次传入的参数会被静默忽略。调用方应始终传同一份实例（当前所有调用方也确实
    ///   只用同一份单例），否则容易造成「以为换了池/缓存/渲染器实际上没换」的误解。
    func configure(blocks: [MarkdownBlock],
                   reasoning: String?,
                   status: MessageStatus,
                   errorText: String?,
                   pool: BlockViewPool,
                   cache: AttributedCache,
                   renderer: AttributedRenderer) {
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

        // 只有失败或被中途停止的消息才展示「重新生成」入口
        retryButton.isHidden = (status != .failed && status != .stopped)

        setNeedsLayout()
    }

    /// 流式增量：只把补丁转发给容器，不做任何全量重建
    func applyPatch(_ patch: BlockPatch) {
        stackView?.applyPatch(patch)
        setNeedsLayout()
    }

    /// `retryLast()` 重新起一轮流之前会先发出 `blocksReset`。
    /// 必须整段清空块视图，否则下一帧到达的补丁会被 `BlockStackView.applyPatch`
    /// 顶部「上一帧未闭合块」特判整段跳过，把新内容 append 在旧的失败内容之后。
    ///
    /// Critical 2：这里必须顺带把「重新生成」按钮也立即隐藏。diffable data source
    /// 对身份不变的行不会重新请求 cell，`configure()` 要等这一轮流
    /// `streamFinished`/`failed` 触发 `invalidateHeight()` 才会再跑一次；
    /// 如果只清空块视图不隐藏按钮，新一轮流式期间按钮会一直留在屏幕上——
    /// 可点但点了被 `retryLast()` 内部的 `guard !state.isStreaming` 静默吞掉，
    /// 而且离屏测量此时已经按 `.streaming` 算出更矮的行高，`layoutSubviews`
    /// 却还在按旧的 `retryButton.isHidden == false` 摆放这个按钮，会压在新内容上。
    func resetBlocks() {
        stackView?.setBlocks([])
        retryButton.isHidden = true
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
        if !retryButton.isHidden {
            height += 32
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
        if !retryButton.isHidden {
            retryButton.frame = CGRect(x: Self.horizontalInset,
                                       y: contentView.bounds.height - Self.verticalInset - 28,
                                       width: 100, height: 28)
        }
    }

    /// 供测试断言补丁确实转发到了容器（`BlockStackView.blockCount` 本身已是公开的）
    var blockCountForTesting: Int { stackView?.blockCount ?? 0 }

    override func prepareForReuse() {
        super.prepareForReuse()
        stackView?.recycleAll()
        reasoningView.isHidden = true
        errorLabel.isHidden = true
        retryButton.isHidden = true
        onLinkTap = nil
        onCodeCopy = nil
        onRetry = nil
    }
}
