import UIKit

/// 竖排块视图的容器。
///
/// 刻意不用 `UIStackView`：流式期间尾块高度每帧都变，
/// 走约束求解的代价远高于自己在 `layoutSubviews` 里算一遍。
///
/// 增量的核心在 `applyPatch`：**已闭合块的视图一旦建好就不再触碰**，
/// 每帧只重新配置最后那个未闭合块。
final class BlockStackView: UIView {

    var onLinkTap: ((URL) -> Void)?
    var onCodeCopy: ((String) -> Void)?

    private let pool: BlockViewPool
    private let cache: AttributedCache
    private let renderer: AttributedRenderer
    private let spacing: CGFloat

    /// 与 `blockViews` 一一对应
    private var blocks: [MarkdownBlock] = []
    private var blockViews: [any BlockView] = []

    /// 最后一个块是否处于未闭合状态
    private var hasOpenBlock = false

    private var cachedWidth: CGFloat = 0
    private var cachedHeights: [CGFloat] = []

    var blockCount: Int { blockViews.count }

    init(pool: BlockViewPool,
         cache: AttributedCache,
         renderer: AttributedRenderer,
         spacing: CGFloat = MarkdownTheme.default.blockSpacing) {
        self.pool = pool
        self.cache = cache
        self.renderer = renderer
        self.spacing = spacing
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    // MARK: - 全量设置

    /// 绑定一条已完成的消息。cell 复用时走这里。
    func setBlocks(_ newBlocks: [MarkdownBlock]) {
        recycleAll()
        for block in newBlocks {
            appendView(for: block)
        }
        hasOpenBlock = newBlocks.last.map { !$0.isSealed } ?? false
        invalidateHeights()
    }

    // MARK: - 增量更新

    /// 应用一次流式补丁。
    ///
    /// 三步：把上一帧的未闭合块「就地固化」；追加本次新闭合的块；
    /// 最后配置新的未闭合块。全程不碰更早的已闭合块视图。
    func applyPatch(_ patch: BlockPatch) {
        var sealedQueue = patch.newlySealed

        // 上一帧的未闭合块，本帧可能已经闭合。复用同一个视图实例就地更新，
        // 避免「闭合瞬间」重建视图造成的闪动。
        if hasOpenBlock, !blockViews.isEmpty {
            if let first = sealedQueue.first,
               first.ordinal == blocks[blocks.count - 1].ordinal {
                sealedQueue.removeFirst()
                updateView(at: blockViews.count - 1, with: first)
                hasOpenBlock = false
            } else if patch.open == nil {
                // 上一帧的未闭合块本帧既没有被闭合，本帧也没有新的开放块——
                // 说明这块被撤回（例如流中止），移除占位视图，不留下悬空的
                // 「未闭合」标记，也不能让它冒充已闭合块滞留在数组里。
                pool.recycle(blockViews[blockViews.count - 1])
                blockViews.removeLast()
                blocks.removeLast()
                hasOpenBlock = false
            }
            // 两个分支都不满足：说明上一帧的未闭合块仍未闭合，且本帧还有新的
            // 开放内容——留给下面 `patch.open` 分支的 `updateView` 原地更新。
        }

        for block in sealedQueue {
            appendView(for: block)
        }

        if let open = patch.open {
            if hasOpenBlock, !blockViews.isEmpty {
                updateView(at: blockViews.count - 1, with: open)
            } else {
                appendView(for: open)
                hasOpenBlock = true
            }
        }

        invalidateHeights()
    }

    func recycleAll() {
        for view in blockViews { pool.recycle(view) }
        blockViews.removeAll()
        blocks.removeAll()
        hasOpenBlock = false
        invalidateHeights()
    }

    // MARK: - 布局与高度

    func heightThatFits(width: CGFloat) -> CGFloat {
        ensureHeights(width: width)
        guard !cachedHeights.isEmpty else { return 0 }
        return cachedHeights.reduce(0, +) + spacing * CGFloat(cachedHeights.count - 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureHeights(width: bounds.width)
        var y: CGFloat = 0
        for (index, view) in blockViews.enumerated() {
            let height = cachedHeights.indices.contains(index) ? cachedHeights[index] : 0
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height + spacing
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: heightThatFits(width: bounds.width))
    }

    /// 供测试断言视图实例身份
    func blockViewForTesting(at index: Int) -> (any BlockView)? {
        blockViews.indices.contains(index) ? blockViews[index] : nil
    }

    // MARK: - 私有

    private func appendView(for block: MarkdownBlock) {
        let view = pool.dequeue(BlockViewKind.kind(for: block.kind))
        configure(view, with: block)
        addSubview(view)
        blockViews.append(view)
        blocks.append(block)
    }

    private func updateView(at index: Int, with block: MarkdownBlock) {
        guard blockViews.indices.contains(index) else { return }
        let needsKind = BlockViewKind.kind(for: block.kind)
        let currentKind = BlockViewKind.kind(for: blocks[index].kind)

        if needsKind != currentKind {
            // 块类型变了（例如段落变成了代码块起始），换视图
            pool.recycle(blockViews[index])
            let view = pool.dequeue(needsKind)
            addSubview(view)
            blockViews[index] = view
        }
        configure(blockViews[index], with: block)
        blocks[index] = block
    }

    private func configure(_ view: any BlockView, with block: MarkdownBlock) {
        let attributed = cache.attributedString(for: block) { [renderer] in
            renderer.render($0)
        }
        view.configure(block: block, attributed: attributed, renderer: renderer)

        if let textView = view as? MarkdownTextBlockView {
            textView.onLinkTap = { [weak self] url in self?.onLinkTap?(url) }
        }
        if let codeView = view as? CodeBlockView {
            codeView.onCopy = { [weak self] code in self?.onCodeCopy?(code) }
        }
    }

    private func invalidateHeights() {
        cachedWidth = 0
        cachedHeights.removeAll()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    private func ensureHeights(width: CGFloat) {
        guard width > 0 else { return }
        guard cachedWidth != width || cachedHeights.count != blockViews.count else { return }
        cachedWidth = width
        cachedHeights = blockViews.map { $0.heightThatFits(width: width) }
    }
}
