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
    private let measurer: TextKitMeasurer
    /// 块间距
    private let spacing: CGFloat

    /// 与 `blockViews` 一一对应
    private var blocks: [MarkdownBlock] = []
    private var blockViews: [any BlockView] = []

    /// 最后一个块是否处于未闭合状态
    private var hasOpenBlock = false

    /// cachedHeights 对应的宽度
    private var cachedWidth: CGFloat = 0
    /// 与 `blockViews` 一一对应；`nil` 表示该槽位待重算。
    ///
    /// 已闭合块的槽位一旦算出就不再被清空——这是 `AttributedCache.height`
    /// 那份「已闭合块只测量一次」承诺在视图层的落地。真正会被清空的只有
    /// 当前未闭合块所在的槽位（在 `updateView` 里），以及宽度变化时的整体重建。
    private var cachedHeights: [CGFloat?] = []

    var blockCount: Int { blockViews.count }

    init(pool: BlockViewPool,
         cache: AttributedCache,
         renderer: AttributedRenderer,
         measurer: TextKitMeasurer,
         spacing: CGFloat = MarkdownTheme.default.blockSpacing) {
        self.pool = pool
        self.cache = cache
        self.renderer = renderer
        self.measurer = measurer
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
        // 整条消息换绑（cell 复用），旧的高度缓存对新内容没有意义，整体重建。
        resetHeightCache()
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
                if !cachedHeights.isEmpty { cachedHeights.removeLast() }
                hasOpenBlock = false
            } else if let first = sealedQueue.first, first.ordinal != blocks[blocks.count - 1].ordinal {
                // 契约外输入：本帧确实有「新闭合块」，但它的 ordinal 对不上上一帧的
                // 未闭合块，且本帧还带着新的开放块——既不是「它被闭合了」（ordinal
                // 应该相等），也不是「它被撤回」（patch.open 应该为 nil）。真实的
                // `StreamingBlockSplitter` 驱动下这个组合不可达：`openBlock.ordinal`
                // 恒等于 `nextOrdinal`，下一次 `seal()` 必然用这个 ordinal 闭合同一个
                // `current`。一旦这个契约被打破（例如未来「重新生成」把切块器错误地
                // 部分重置），继续往下走会把 sealedQueue 追加到旧的未闭合视图后面，
                // 再用 patch.open 覆盖那个「本应是已闭合」的块，静默破坏「已闭合块只
                // 增不改」的不变量。这里用 assertionFailure 快速失败：Debug 直接崩，
                // Release 下 assertionFailure 是空操作，行为退化为「维持上一帧未闭合
                // 块不变、后续按原逻辑继续」，不新增风险。
                assertionFailure("BlockStackView.applyPatch：sealedQueue.first 的 ordinal 与上一帧未闭合块不匹配，这是契约外输入")
            }
            // 若 sealedQueue.first 为 nil 且 patch.open 非 nil：上一帧的未闭合块仍未
            // 闭合，本帧只是继续追加内容——留给下面 patch.open 分支的 updateView
            // 原地更新，这是最常见的流式续写路径。
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
        // 注意：这里不再无条件清空整个 cachedHeights——appendView/updateView/
        // 撤回分支已经各自把受影响槽位标记为待重算，已闭合块的槽位原样保留。
    }

    /// 全部块视图还回复用池
    func recycleAll() {
        for view in blockViews { pool.recycle(view) }
        blockViews.removeAll()
        blocks.removeAll()
        hasOpenBlock = false
        resetHeightCache()
    }

    // MARK: - 布局与高度

    /// 各块高度之和加块间距
    func heightThatFits(width: CGFloat) -> CGFloat {
        ensureHeights(width: width)
        guard !cachedHeights.isEmpty else { return 0 }
        let heights = cachedHeights.map { $0 ?? 0 }
        return heights.reduce(0, +) + spacing * CGFloat(heights.count - 1)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ensureHeights(width: bounds.width)
        var y: CGFloat = 0
        for (index, view) in blockViews.enumerated() {
            let height = cachedHeights.indices.contains(index) ? (cachedHeights[index] ?? 0) : 0
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

    /// 从池里借一个视图追加到末尾
    private func appendView(for block: MarkdownBlock) {
        let view = pool.dequeue(BlockViewKind.kind(for: block.kind))
        configure(view, with: block)
        addSubview(view)
        blockViews.append(view)
        blocks.append(block)
        // 新槽位还没算过高度；只在 cachedHeights 已经和旧的 blockViews 对齐时才
        // 追加占位，否则等下一次 ensureHeights 按 blockViews.count 统一重建。
        if cachedHeights.count == blockViews.count - 1 {
            cachedHeights.append(nil)
        }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// 原地更新某个槽位，块类型变了就换视图
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
        // 这个槽位的内容变了（原地固化闭合块，或未闭合块继续追加文字），
        // 唯有它需要重新测量——其余已闭合槽位保持原样，这正是 I1 要修的性能点。
        if cachedHeights.indices.contains(index) {
            cachedHeights[index] = nil
        }
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// 取（缓存的）属性串配置视图，并转发链接点击与代码复制
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

    /// 整体重建高度缓存：仅用于「换绑一条全新消息」（`setBlocks`/`recycleAll`）。
    /// 流式增量路径（`applyPatch`）绝不调用这个方法——它会连已闭合块的高度也
    /// 一并清空，正是 I1 要修的那个 O(n²) 形状。
    private func resetHeightCache() {
        cachedWidth = 0
        cachedHeights.removeAll()
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    /// 按需补算高度：宽度变化时整体重建（不同宽度下已闭合块的高度本就该
    /// 重新测量）；宽度不变时只重算 `cachedHeights` 里被标记为 `nil` 的槽位——
    /// 已闭合块一旦算过就不会再被标脏，`AttributedCache.height` 那份「已闭合块
    /// 只测量一次」的承诺才不会被这层局部缓存架空。
    private func ensureHeights(width: CGFloat) {
        guard width > 0 else { return }
        if cachedWidth != width {
            cachedWidth = width
            cachedHeights = Array(repeating: nil, count: blockViews.count)
        } else if cachedHeights.count != blockViews.count {
            // 正常流程下 appendView/updateView/撤回分支已经让 cachedHeights 与
            // blockViews 保持同步；这里是防御性兜底，理论不可达。
            cachedHeights = Array(repeating: nil, count: blockViews.count)
        }
        for index in blocks.indices where cachedHeights[index] == nil {
            cachedHeights[index] = computeHeight(at: index, width: width)
        }
    }

    /// 已闭合块走 `AttributedCache.height`（按 block 内容 + 量化宽度缓存，
    /// 命中时完全不触碰 `UITextView`/TextKit）；未闭合块每帧都在变，直接测量。
    ///
    /// 未闭合块仍走视图测量：它的属性串这一帧刚在 `configure` 里设进视图，
    /// 为了测高再渲染一份纯属浪费，而未闭合块必然有活视图在手。
    private func computeHeight(at index: Int, width: CGFloat) -> CGFloat {
        let block = blocks[index]
        let view = blockViews[index]
        guard block.isSealed else {
            return view.heightThatFits(width: width)
        }
        return cache.height(for: block, width: width, render: { [renderer] in
            renderer.render($0)
        }, measure: { [self] attributed in
            sealedHeight(attributed, kind: block.kind, view: view, width: width)
        })
    }

    /// 已闭合块的高度。能交给测量器的类型就完全不碰视图，其余回退到视图测量。
    private func sealedHeight(_ attributed: NSAttributedString,
                              kind: MarkdownBlockKind,
                              view: any BlockView,
                              width: CGFloat) -> CGFloat {
        guard TextKitMeasurer.canMeasure(kind) else {
            return view.heightThatFits(width: width)
        }
        // 代码块不换行，宽度传 nil；其余按块类型扣掉装饰占的宽度。
        let available: CGFloat?
        if case .codeFence = kind {
            available = nil
        } else {
            available = BlockMetrics.textContentWidth(for: kind, in: width)
        }
        let measured = measurer.height(of: attributed, width: available)
            + BlockMetrics.chromeHeight(for: kind)

        #if DEBUG
        // 影子校验：Debug 下两条路都算一遍，抓真实使用中的漂移，而不只是测试语料
        // 里的。这里是 AttributedCache 的 measure 闭包，每个「内容 + 量化宽度」
        // 只会进来一次，所以不会打破「已闭合块只测量一次」那条承诺。
        let fromView = view.heightThatFits(width: width)
        assert(abs(fromView - measured) < 0.5,
               "测量器与视图测高不一致：视图 \(fromView)，测量器 \(measured)，块类型 \(kind)")
        #endif
        return measured
    }
}
