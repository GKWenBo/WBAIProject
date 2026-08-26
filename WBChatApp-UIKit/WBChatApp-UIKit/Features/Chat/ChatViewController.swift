import UIKit

final class ChatViewController: UIViewController {

    // MARK: - 依赖

    private let viewModel: ChatViewModel
    private let renderer: AttributedRenderer
    private let cache: AttributedCache
    private let pool: BlockViewPool
    private let autoScroll = AutoScrollController()

    // MARK: - 视图

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Theme.background
        tableView.keyboardDismissMode = .interactive
        tableView.accessibilityIdentifier = "chat.tableView"
        tableView.translatesAutoresizingMaskIntoConstraints = false
        return tableView
    }()

    private let inputBar = InputBarView()
    private let scrollToBottomButton = ScrollToBottomButton()

    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    /// 行高缓存。键是消息 id，值是当前宽度下的高度。
    private var heightCache: [String: CGFloat] = [:]
    private var cachedWidth: CGFloat = 0

    /// 正在流式的那条消息，用来直接拿 cell 打补丁
    private var streamingMessageID: String?

    /// 离屏测量专用的常驻 cell（助手/用户各一个），不加入视图层级。
    /// 关键：AssistantMessageCell 内部的 BlockStackView 持有的是共享的 BlockViewPool，
    /// 如果每次测量都 `AssistantMessageCell(...)` 新建一个，上一次测量借走的块视图
    /// 永远不会归还给 pool——常驻并在下次 configure 前 `prepareForReuse()`，
    /// 才能让借出去的块视图在下一次测量前先还回池子，收支平衡。
    private lazy var measuringAssistantCell = AssistantMessageCell(style: .default, reuseIdentifier: nil)
    private lazy var measuringUserCell = UserMessageCell(style: .default, reuseIdentifier: nil)

    init(viewModel: ChatViewModel,
         renderer: AttributedRenderer,
         cache: AttributedCache,
         pool: BlockViewPool) {
        self.viewModel = viewModel
        self.renderer = renderer
        self.cache = cache
        self.pool = pool
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("不支持 Storyboard") }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        setUpViews()
        setUpDataSource()
        bindViewModel()
        bindAutoScroll()
        viewModel.loadHistory()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if cachedWidth != tableView.bounds.width {
            cachedWidth = tableView.bounds.width
            heightCache.removeAll()
            tableView.reloadData()
        }
    }

    // MARK: - 装配

    private func setUpViews() {
        view.addSubview(tableView)
        view.addSubview(inputBar)
        view.addSubview(scrollToBottomButton)
        inputBar.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: inputBar.topAnchor),

            inputBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // keyboardLayoutGuide 自动跟随键盘，不需要手写通知监听
            inputBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),

            scrollToBottomButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: inputBar.topAnchor, constant: -12),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 36),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 36),
        ])

        tableView.register(AssistantMessageCell.self,
                           forCellReuseIdentifier: AssistantMessageCell.reuseIdentifier)
        tableView.register(UserMessageCell.self,
                           forCellReuseIdentifier: UserMessageCell.reuseIdentifier)
        tableView.delegate = self

        inputBar.onSend = { [weak self] text in
            self?.autoScroll.didSendMessage()
            self?.viewModel.send(text)
        }
        inputBar.onStop = { [weak self] in self?.viewModel.stop() }
        inputBar.onHeightChange = { [weak self] in self?.stickToBottomIfNeeded() }

        scrollToBottomButton.addTarget(self, action: #selector(handleScrollToBottom),
                                       for: .touchUpInside)
    }

    private func setUpDataSource() {
        dataSource = UITableViewDiffableDataSource<Int, String>(tableView: tableView) {
            [weak self] tableView, indexPath, messageID in
            guard let self,
                  let message = self.viewModel.state.messages.first(where: { $0.id == messageID })
            else { return UITableViewCell() }

            switch message.role {
            case .user, .system:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: UserMessageCell.reuseIdentifier, for: indexPath) as! UserMessageCell
                cell.configure(text: message.text)
                return cell

            case .assistant:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: AssistantMessageCell.reuseIdentifier, for: indexPath) as! AssistantMessageCell
                cell.configure(blocks: self.viewModel.blocks(for: message.id),
                               reasoning: message.reasoning,
                               status: message.status,
                               errorText: message.errorText,
                               pool: self.pool,
                               cache: self.cache,
                               renderer: self.renderer)
                cell.onCodeCopy = { _ in Haptics.success() }
                cell.onLinkTap = { url in UIApplication.shared.open(url) }
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
    }

    // MARK: - 绑定

    private func bindViewModel() {
        viewModel.onOutput = { [weak self] output in
            guard let self else { return }
            switch output {
            case .stateChanged(let state):
                self.applySnapshot(state)
                self.inputBar.setStreaming(state.isStreaming)
                self.streamingMessageID = state.isStreaming ? state.messages.last?.id : nil

            case .blocksReset(let messageID):
                self.resetBlocks(messageID: messageID)

            case .blocksPatched(let messageID, let patch):
                self.applyPatch(messageID: messageID, patch: patch)

            case .reasoningUpdated(let messageID, let text):
                self.applyReasoning(messageID: messageID, text: text)

            case .streamFinished(let messageID):
                self.streamingMessageID = nil
                self.invalidateHeight(for: messageID)

            case .failed(_, let messageID):
                self.streamingMessageID = nil
                if let messageID { self.invalidateHeight(for: messageID) }
            }
        }
    }

    private func bindAutoScroll() {
        autoScroll.onModeChange = { [weak self] mode in
            self?.scrollToBottomButton.setVisible(mode == .detached)
        }
    }

    // MARK: - 结构性变化

    private func applySnapshot(_ state: ChatViewModel.State) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.messages.map(\.id))

        // 内容变化的行不靠 snapshot 刷新，交给增量补丁
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.stickToBottomIfNeeded()
        }
    }

    // MARK: - 流式增量

    /// `retryLast()` 重新起一轮流之前，ViewModel 会先发出这个信号：
    /// 上一轮失败/已完成的块视图必须先清空，否则新一轮的第一个补丁到达时，
    /// `BlockStackView.applyPatch` 顶部的「上一帧未闭合块」特判会因为
    /// `hasOpenBlock == false`（上一轮流结束时已经把 open 块封口）而整段跳过，
    /// 直接把新内容 append 在旧内容后面，产生重复错位显示。
    /// 只处理可视区内的 cell：不可见的 cell 下次 `configure` 时，
    /// `viewModel.blocks(for:)` 已经是空数组，走 `configure` 路径天然正确。
    private func resetBlocks(messageID: String) {
        guard let indexPath = indexPath(for: messageID),
              let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else { return }
        cell.resetBlocks()
        heightCache[messageID] = nil
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    /// 关键路径：拿到 cell 实例直接打补丁，**不走 reloadRows**。
    private func applyPatch(messageID: String, patch: BlockPatch) {
        guard let indexPath = indexPath(for: messageID) else { return }
        guard let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else {
            // 不在可视区就只更新高度缓存，等 cell 复用时由 configure 重建
            invalidateHeight(for: messageID)
            return
        }

        cell.applyPatch(patch)

        let newHeight = cell.heightThatFits(width: tableView.bounds.width)
        let oldHeight = heightCache[messageID]
        heightCache[messageID] = newHeight

        // 高度真的变了才惊动 tableView
        if oldHeight == nil || abs(oldHeight! - newHeight) > 0.5 {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
        stickToBottomIfNeeded()
    }

    private func applyReasoning(messageID: String, text: String) {
        guard let indexPath = indexPath(for: messageID),
              let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else { return }
        cell.updateReasoning(text)

        let newHeight = cell.heightThatFits(width: tableView.bounds.width)
        let oldHeight = heightCache[messageID]
        heightCache[messageID] = newHeight

        // 与 applyPatch 一致：高度真的变了才惊动 tableView
        if oldHeight == nil || abs(oldHeight! - newHeight) > 0.5 {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
        stickToBottomIfNeeded()
    }

    /// 偏离简报：原版直接调用 `tableView.reloadRows(at:with:)`。
    /// iOS 15+ 起，tableView 的 dataSource 是 `UITableViewDiffableDataSource` 时，
    /// 直接调用 `reloadRows`/`insertRows`/`deleteRows` 等结构性 mutation API 会触发
    /// `NSInternalInconsistencyException`：
    /// "UITableView must be updated via the UITableViewDiffableDataSource APIs...
    /// please do not call mutation APIs directly on UITableView."
    /// 实测：发一条消息、流结束时必现崩溃。改为通过 `reconfigureItems` 走
    /// diffable data source 自己的 apply 通道——cellProvider 里的 `dequeueReusableCell`
    /// 对已可见的 indexPath 会返回同一个 cell 实例，所以这里等价于「原地刷新该行」，
    /// 不会产生插入/删除动画，也不违反 diffable data source 的所有权约束。
    /// 注意：`beginUpdates()/endUpdates()`（`applyPatch`/`applyReasoning`/`resetBlocks`
    /// 里用来强制重新查询行高的手法）之间没有夹带任何插入/删除/reload 调用，
    /// 经反复流式测试验证不触发该断言，予以保留。
    private func invalidateHeight(for messageID: String) {
        heightCache[messageID] = nil
        guard dataSource.indexPath(for: messageID) != nil else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems([messageID])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func indexPath(for messageID: String) -> IndexPath? {
        dataSource.indexPath(for: messageID)
    }

    // MARK: - 贴底

    /// pinned 状态下贴底。一律无动画，避免与减速动画互相打断。
    private func stickToBottomIfNeeded() {
        guard autoScroll.shouldStickToBottom else { return }
        let bottomOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        guard bottomOffset > -tableView.adjustedContentInset.top else { return }

        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        autoScroll.endProgrammaticScroll()
    }

    @objc private func handleScrollToBottom() {
        autoScroll.didTapScrollToBottom()
        let bottomOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: max(0, bottomOffset)), animated: true)
        // 动画结束前保持标记，避免中途被判成用户滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.autoScroll.endProgrammaticScroll()
        }
    }

    private var distanceToBottom: CGFloat {
        let maxOffset = tableView.contentSize.height
            - tableView.bounds.height + tableView.adjustedContentInset.bottom
        return max(0, maxOffset - tableView.contentOffset.y)
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let messageID = dataSource.itemIdentifier(for: indexPath) else { return 0 }
        if let cached = heightCache[messageID] { return cached }

        guard let message = viewModel.state.messages.first(where: { $0.id == messageID }) else {
            return 0
        }
        let height = measureHeight(for: message, width: tableView.bounds.width)
        heightCache[messageID] = height
        return height
    }

    /// 离屏测量：复用常驻的测量 cell，避免创建临时视图（也避免污染共享的 BlockViewPool，
    /// 见 `measuringAssistantCell` 的注释）
    private func measureHeight(for message: ChatViewModel.MessageViewData,
                               width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        switch message.role {
        case .user, .system:
            let cell = measuringUserCell
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 0)
            cell.configure(text: message.text)
            return cell.heightThatFits(width: width)
        case .assistant:
            let cell = measuringAssistantCell
            // 先把上一次测量借走的块视图还给池子，再借新的
            cell.prepareForReuse()
            cell.frame = CGRect(x: 0, y: 0, width: width, height: 0)
            cell.configure(blocks: viewModel.blocks(for: message.id),
                           reasoning: message.reasoning,
                           status: message.status,
                           errorText: message.errorText,
                           pool: pool, cache: cache, renderer: renderer)
            return cell.heightThatFits(width: width)
        }
    }

    // MARK: 滚动回调全部转发给状态机

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        autoScroll.willBeginDragging(offsetY: scrollView.contentOffset.y)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        autoScroll.didScroll(offsetY: scrollView.contentOffset.y,
                             isTracking: scrollView.isTracking)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        autoScroll.didEndDragging(willDecelerate: decelerate,
                                  distanceToBottom: distanceToBottom)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        autoScroll.didEndDecelerating(distanceToBottom: distanceToBottom)
    }
}
