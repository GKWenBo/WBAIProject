import UIKit

/// 助手消息 cell。左对齐、无气泡背景，贴合 ChatGPT 的排版。
final class AssistantMessageCell: UITableViewCell {

    static let reuseIdentifier = "AssistantMessageCell"

    private static let horizontalInset: CGFloat = 16
    private static let verticalInset: CGFloat = 10

    /// 正文块容器，首次 configure 时按注入的依赖创建
    private var stackView: BlockStackView?

    private let reasoningView: ReasoningSectionView = {
        let view = ReasoningSectionView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    /// 失败/中断/截断等提示文案
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
    /// 点击操作栏的「复制」
    var onCopy: (() -> Void)?
    /// 点击操作栏的「重新生成」或「重试保存」
    var onRetry: (() -> Void)?
    /// C2 修复：思考过程折叠区被展开/收起时触发。`ReasoningSectionView.onToggle`
    /// 本身只负责喊一嗓子「我被点了」，具体「行高要不要重新查询、tableView 要不要
    /// beginUpdates/endUpdates」是控制器层的事——这里只做转发。
    var onReasoningToggled: (() -> Void)?

    /// 常驻操作栏，始终占位，见 `MessageActionBar` 的说明
    private let actionBar = MessageActionBar()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.addSubview(reasoningView)
        contentView.addSubview(errorLabel)
        contentView.addSubview(actionBar)
        reasoningView.onToggle = { [weak self] in self?.onReasoningToggled?() }
        bindActionBar()
    }

    /// 操作栏的回调转发到 cell 的公开回调；`prepareForReuse` 里 `actionBar.reset()`
    /// 会清掉这层转发，所以复位后要重新接上
    private func bindActionBar() {
        actionBar.onCopy = { [weak self] in self?.onCopy?() }
        actionBar.onTrailing = { [weak self] in self?.onRetry?() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    /// - Note: `pool` / `cache` / `renderer` / `measurer` 只在 cell 首次创建内部的
    ///   `BlockStackView` 时生效；cell 被复用（第二次及以后调用本方法）时会沿用首次
    ///   捕获的那几个实例，本次传入的参数会被静默忽略。调用方应始终传同一份实例
    ///   （当前所有调用方也确实只用同一份单例），否则容易造成「以为换了池/缓存/
    ///   渲染器/测量器实际上没换」的误解。
    func configure(blocks: [MarkdownBlock],
                   reasoning: String?,
                   status: MessageStatus,
                   errorText: String?,
                   pool: BlockViewPool,
                   cache: AttributedCache,
                   renderer: AttributedRenderer,
                   measurer: TextKitMeasurer,
                   canCopy: Bool = false,
                   trailingAction: MessageActionBar.Trailing = .none) {
        let stack: BlockStackView
        if let existing = stackView {
            stack = existing
        } else {
            stack = BlockStackView(pool: pool, cache: cache,
                                   renderer: renderer, measurer: measurer)
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

        // 流式中的消息只占位不出按钮；其余由调用方按「是否最后一条、能否发送」决定
        let isStreaming = status == .streaming
        actionBar.configure(canCopy: canCopy && !isStreaming,
                            trailing: isStreaming ? .none : trailingAction)

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
    /// Critical 2：这里必须顺带把操作栏按钮也立即隐藏。diffable data source
    /// 对身份不变的行不会重新请求 cell，`configure()` 要等这一轮流
    /// `streamFinished`/`failed` 触发 `invalidateHeight()` 才会再跑一次；
    /// 如果只清空块视图不隐藏按钮，新一轮流式期间按钮会一直留在屏幕上——
    /// 可点但点了被 `retryLast()` 内部的 `guard !state.isStreaming` 静默吞掉。
    /// 操作栏本身保持占位，行高不因按钮显隐变化。
    func resetBlocks() {
        stackView?.setBlocks([])
        actionBar.configure(canCopy: false, trailing: .none)
        setNeedsLayout()
    }

    func updateReasoning(_ text: String) {
        reasoningView.isHidden = text.isEmpty
        reasoningView.setText(text)
        setNeedsLayout()
    }

    /// 纯计算行高：上下留白 + 思考区 + 正文 + 提示 + 操作栏，与 layoutSubviews 保持一致
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
        height += MessageActionBar.height
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
            y += height + 8
        }
        // 紧跟内容摆放而不是贴 cell 底部：重新生成期间行高可能被控制器撑高
        // （见 `ChatViewController.holdHeightForRegeneration`），多出来的留白在操作栏下方
        actionBar.frame = CGRect(x: Self.horizontalInset, y: y,
                                 width: contentWidth, height: MessageActionBar.height)
    }

    /// 供测试断言补丁确实转发到了容器（`BlockStackView.blockCount` 本身已是公开的）
    var blockCountForTesting: Int { stackView?.blockCount ?? 0 }

    /// 供测试断言：思考过程折叠区当前是否展开
    var reasoningExpandedForTesting: Bool { reasoningView.isExpandedForTesting }

    /// 供测试直接触发一次「展开/收起」点击,不用真的构造 UITapGestureRecognizer
    func simulateReasoningToggleForTesting() {
        reasoningView.simulateToggleForTesting()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stackView?.recycleAll()
        reasoningView.isHidden = true
        // C2 修复：展开态是 ReasoningSectionView 自己的视图状态，不会因为
        // isHidden = true 或换绑新消息就自动复位，必须显式收起。
        reasoningView.collapse()
        errorLabel.isHidden = true
        actionBar.reset()
        bindActionBar()
        onLinkTap = nil
        onCodeCopy = nil
        onCopy = nil
        onRetry = nil
        onReasoningToggled = nil
    }
}
