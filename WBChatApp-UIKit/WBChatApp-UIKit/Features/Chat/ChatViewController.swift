import UIKit

/// 聊天页：消息列表 + 输入栏 + 语音输入。
///
/// 两条刷新通道：
/// - 结构变化（增删消息、状态切换）走 diffable snapshot；
/// - 流式增量直接拿到可见 cell 打补丁，只在行高变化时 begin/endUpdates，不 reload。
/// 行高由离屏测量 + `heightCache` 提供，不依赖 Auto Layout 自适应。
final class ChatViewController: UIViewController {

    // MARK: - 依赖

    private let viewModel: ChatViewModel
    // 以下渲染组件全局共享，由 AppContainer 注入
    private let renderer: AttributedRenderer
    private let cache: AttributedCache
    private let pool: BlockViewPool
    private let measurer: TextKitMeasurer
    /// 贴底/脱离的滚动状态机
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

    /// 非 private：语音状态机测试需要通过它触发 onMicTap、读取输入框文字来驱动/校验
    /// `startVoiceInput` / `finishVoiceInput` 的状态机，而不是复制一份状态机逻辑去测替身。
    let inputBar = InputBarView()
    private let scrollToBottomButton = ScrollToBottomButton()

    // MARK: - 语音输入

    private let transcriber: SpeechTranscribing
    /// getter 非 private：测试要靠它判断浮层是否已出现（等异步授权走完）、
    /// 以及驱动 onConfirm/onCancel；setter 仍是 private，外部不能直接摆浮层。
    private(set) var recordingOverlay: RecordingOverlayView?
    /// getter 非 private：测试靠 `await speechTask?.value` 等语音会话彻底收尾，
    /// 不用瞎猜 yield 次数。同时也是 Critical 2 的同步重入锁——见 `startVoiceInput()`。
    private(set) var speechTask: Task<Void, Never>?
    /// 本次语音会话最新的识别文本
    private var transcribedText = ""

    /// 单 section，item 为消息 id
    private var dataSource: UITableViewDiffableDataSource<Int, String>!

    /// 行高缓存。键是消息 id，值是当前宽度下的高度。
    private var heightCache: [String: CGFloat] = [:]
    /// heightCache 对应的列表宽度，宽度变化时整体失效
    private var cachedWidth: CGFloat = 0

    /// 正在流式的那条消息，用来直接拿 cell 打补丁
    private var streamingMessageID: String?

    /// 「重新生成」时给那一行定的最低行高，见 `rowHeight(_:for:)`
    private var regenerationFloor: (messageID: String, height: CGFloat)?

    /// 离屏测量专用的常驻 cell（助手/用户各一个），不加入视图层级。
    /// 关键：AssistantMessageCell 内部的 BlockStackView 持有的是共享的 BlockViewPool，
    /// 如果每次测量都 `AssistantMessageCell(...)` 新建一个，上一次测量借走的块视图
    /// 永远不会归还给 pool——常驻并在下次 configure 前 `prepareForReuse()`，
    /// 才能让借出去的块视图在下一次测量前先还回池子，收支平衡。
    private lazy var measuringAssistantCell = AssistantMessageCell(style: .default, reuseIdentifier: nil)
    private lazy var measuringUserCell = UserMessageCell(style: .default, reuseIdentifier: nil)

    /// `transcriber` 带默认值：`AppContainer` 现有的调用点不用改，
    /// 只有测试需要注入替身时才传参。
    init(viewModel: ChatViewModel,
         renderer: AttributedRenderer,
         cache: AttributedCache,
         pool: BlockViewPool,
         measurer: TextKitMeasurer,
         transcriber: SpeechTranscribing = SystemSpeechTranscriber()) {
        self.viewModel = viewModel
        self.renderer = renderer
        self.cache = cache
        self.pool = pool
        self.measurer = measurer
        self.transcriber = transcriber
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

    /// 恢复草稿与阅读位置，恢复订阅
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let position = viewModel.readingPosition
        autoScroll.restore(pinned: position.pinned)
        viewModel.setVisible(true)
        inputBar.setText(viewModel.draft)
        tableView.layoutIfNeeded()
        if position.pinned { stickToBottomIfNeeded() }
        else { tableView.setContentOffset(CGPoint(x: 0, y: position.offset), animated: false) }
    }

    /// 保存草稿与阅读位置，退订（生成在协调器里继续）
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.draft = inputBar.text
        viewModel.readingPosition = .init(offset: tableView.contentOffset.y, pinned: autoScroll.shouldStickToBottom)
        viewModel.setVisible(false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if cachedWidth != tableView.bounds.width {
            cachedWidth = tableView.bounds.width
            heightCache.removeAll()
            // 下限是按旧宽度量出来的，换宽度后已无意义
            regenerationFloor = nil
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
            // I3 修复：左右也绑定到 safeAreaLayoutGuide,而不是只绑顶部。
            // `UITableView.insetsContentViewsToSafeArea` 默认为 true,会让每个 cell 的
            // contentView 再叠加一次安全区内边距;若 tableView 自己没有先贴safe area
            // （之前只绑了 view.leadingAnchor/trailingAnchor),横屏 iPhone/iPad 上
            // contentView.bounds.width 会比 tableView.bounds.width 窄一个安全区宽度——
            // 离屏测量用前者会算出偏小的行高,layoutSubviews 再按后者排版,文字被裁。
            // 让 tableView 自身先吃掉安全区,两个宽度就恒等,离屏测量与实际布局用的
            // 是同一个数。
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
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
            guard let self else { return false }
            let accepted = await self.viewModel.send(text)
            if accepted { self.autoScroll.didSendMessage() }
            return accepted
        }
        inputBar.onTextChanged = { [weak self] in self?.viewModel.draft = $0 }
        inputBar.setText(viewModel.draft)
        inputBar.onStop = { [weak self] in self?.viewModel.stop() }
        inputBar.onHeightChange = { [weak self] in self?.stickToBottomIfNeeded() }
        inputBar.onMicTap = { [weak self] in self?.startVoiceInput() }

        scrollToBottomButton.addTarget(self, action: #selector(handleScrollToBottom),
                                       for: .touchUpInside)
    }

    /// 按角色配置用户/助手 cell，并接好 cell 上的交互回调
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
                               reasoning: viewModel.displayReasoning(for: message.id),
                               status: message.status,
                               errorText: message.errorText,
                               pool: self.pool,
                               cache: self.cache,
                               renderer: self.renderer,
                               measurer: self.measurer,
                               canCopy: !message.text.isEmpty,
                               trailingAction: self.trailingAction(for: message))
                cell.onCodeCopy = { _ in Haptics.success() }
                cell.onCopy = { [weak self] in
                    self?.handleCopyTapped(messageID: message.id)
                }
                cell.onLinkTap = { url in UIApplication.shared.open(url) }
                // Critical 1：闭包在这里按当前这一行的 message.id 捕获,
                // 转发前交给 handleRetryTapped 用点击那一刻最新的 state 复核一遍,
                // 不能无脑调 retryLast()——它内部永远只操作 state.messages.last,
                // 如果按钮属于一条已经不是最后一条的助手消息(cell 复用/滚动残留),
                // 会把点 A 的按钮误重试成当前最后一条 B。
                cell.onRetry = { [weak self] in
                    self?.handleRetryTapped(messageID: message.id)
                }
                // C2 修复：折叠区展开/收起会改变这条 cell 的高度,但那之前没有
                // 任何地方给 onToggle 赋值,tableView 也就永远不会重新查询行高。
                cell.onReasoningToggled = { [weak self] in
                    self?.handleReasoningToggled(messageID: message.id)
                }
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
    }

    // MARK: - 绑定

    /// ViewModel 输出 → 列表刷新 / cell 补丁 / 弹窗
    private func bindViewModel() {
        viewModel.onOutput = { [weak self] output in
            guard let self else { return }
            switch output {
            case .stateChanged(let state):
                self.applySnapshot(state)
                self.inputBar.setStreaming(state.isStreaming)
                self.inputBar.setCanSend(state.canSend)
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

            case .failed(let error, let messageID):
                if let messageID {
                    self.streamingMessageID = nil
                    self.invalidateHeight(for: messageID)
                } else { self.presentErrorAlert(error == .storage ? "消息未保存，请重试" : error.userMessage) }
            }
        }
    }

    private func bindAutoScroll() {
        autoScroll.onModeChange = { [weak self] mode in
            self?.scrollToBottomButton.setVisible(mode == .detached)
        }
    }

    // MARK: - 结构性变化

    /// 结构/状态变化：重建 snapshot，已有行原地 reconfigure，清空行高缓存
    private func applySnapshot(_ state: ChatViewModel.State) {
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(state.messages.map(\.id))

        // 有新消息追加（用户又发了一条）时，视口本来就要整体上移，重新生成的行高下限随之作废
        if let floor = regenerationFloor, state.messages.last?.id != floor.messageID {
            regenerationFloor = nil
        }

        // 这里只处理结构/状态变化；token 增量仍走补丁。保留旧内容时也要立刻隐藏重试按钮。
        let existing = Set(dataSource.snapshot().itemIdentifiers)
        snapshot.reconfigureItems(state.messages.map(\.id).filter { existing.contains($0) })
        heightCache.removeAll()
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
        // 校验：补丁的 messageID 理应恒等于当前流式消息。`streamingMessageID`
        // 由 `stateChanged` 在进入流式态时设置、`streamFinished`/`failed` 时清空，
        // 与 ViewModel 侧「同一时刻只有一条流」的不变量对应；一旦不一致，说明
        // 补丁被错误地打到了另一条消息上（例如两处状态更新的顺序被意外打乱），
        // 这里 assert 提前暴露，而不是让 UI 静默显示错位的内容。
        assert(streamingMessageID == nil || streamingMessageID == messageID,
              "applyPatch 收到的 messageID(\(messageID)) 与当前流式消息(\(streamingMessageID ?? "nil")) 不一致")
        guard let indexPath = indexPath(for: messageID) else { return }
        guard let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else {
            // I2 修复：不在可视区时只失效高度缓存,不能调用 invalidateHeight(for:)——
            // 那是走 snapshot() 拷贝 + reconfigureItems + apply 的结构性刷新通道,
            // 流式消息一旦滚出可视区,每帧都会触发一次全量 diff,而 apply 内部还会
            // 让 tableView 重新查询行高、间接把这条消息的块视图全量测量一遍。
            // 这里只清缓存值就够了：真正的重新 configure 交给 cell 滚回可视区时
            // cellProvider 的 dequeueReusableCell → configure(blocks:) 路径,
            // 那时 viewModel.blocks(for:) 已经是最新的完整块数组。
            heightCache[messageID] = nil
            return
        }

        cell.applyPatch(patch)

        let newHeight = rowHeight(cell.heightThatFits(width: tableView.bounds.width), for: messageID)
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

    /// 思考内容增量：更新折叠区文本并按需重算行高
    private func applyReasoning(messageID: String, text: String) {
        guard let indexPath = indexPath(for: messageID),
              let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else { return }
        cell.updateReasoning(text)

        let newHeight = rowHeight(cell.heightThatFits(width: tableView.bounds.width), for: messageID)
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

    /// 用户手动展开/收起「思考过程」触发：与 `applyPatch`/`applyReasoning` 走
    /// 同一套「重算高度 + beginUpdates/endUpdates」路径,但不 `stickToBottomIfNeeded()`——
    /// 用户主动展开一段折叠内容时不该把视口强行拽到底部。
    private func handleReasoningToggled(messageID: String) {
        guard let indexPath = indexPath(for: messageID),
              let cell = tableView.cellForRow(at: indexPath) as? AssistantMessageCell else { return }

        let newHeight = rowHeight(cell.heightThatFits(width: tableView.bounds.width), for: messageID)
        let oldHeight = heightCache[messageID]
        heightCache[messageID] = newHeight

        if oldHeight == nil || abs(oldHeight! - newHeight) > 0.5 {
            UIView.performWithoutAnimation {
                tableView.beginUpdates()
                tableView.endUpdates()
            }
        }
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

    /// Critical 1：`AssistantMessageCell.onRetry` 只是「这颗按钮被点了」的信号,
    /// 不代表点它的这条消息现在还是最后一条助手消息——cell 可能残留着一条
    /// 已经不是最后一条的失败消息的按钮。真正转发给 `retryLast()` 之前,
    /// 必须用点击那一刻最新的 `viewModel.state` 重新核对,标准与
    /// `trailingAction(for:)` 决定按钮显隐的判断保持一致。
    private func handleRetryTapped(messageID: String) {
        guard !viewModel.state.isStreaming,
              viewModel.state.messages.last?.id == messageID else { return }
        if viewModel.state.hasUnsavedContent {
            Task { await viewModel.retrySave() }
        } else {
            autoScroll.didSendMessage()
            holdHeightForRegeneration(messageID: messageID)
            Task { await viewModel.retryLast() }
        }
    }

    /// 重新生成防跳动：首个增量到达时 `blocksReset` 会把旧答案整段清空，
    /// 行高骤降，贴底逻辑随即把视口往回拉一大截，再随新内容逐帧往上推——
    /// 肉眼看就是整屏先往下跳、再往上爬。这里把该行当前高度记为下限，
    /// 新内容在原位置从上往下写，不足的部分留白；直到用户再发一条消息
    /// （视口本来就要整体上移）才撤销下限，结束时也不会因为新答案更短而回缩。
    private func holdHeightForRegeneration(messageID: String) {
        guard let indexPath = indexPath(for: messageID) else { return }
        let current = heightCache[messageID] ?? tableView.rectForRow(at: indexPath).height
        guard current > 0 else { return }
        regenerationFloor = (messageID, current)
    }

    /// 测量高度叠加重新生成的行高下限
    private func rowHeight(_ measured: CGFloat, for messageID: String) -> CGFloat {
        guard let floor = regenerationFloor, floor.messageID == messageID else { return measured }
        return max(measured, floor.height)
    }

    /// 操作栏右侧按钮：只有最后一条助手消息才有。落库失败时给「重试保存」,
    /// 能发送时给「重新生成」,其余（生成中、准备中）不出按钮。
    private func trailingAction(for message: ChatViewModel.MessageViewData) -> MessageActionBar.Trailing {
        let state = viewModel.state
        guard message.role == .assistant, message.id == state.messages.last?.id else { return .none }
        if state.hasUnsavedContent { return .retrySave }
        return state.canSend ? .regenerate : .none
    }

    /// 流式期间 `message.text` 可能还是旧值，`displayText(for:)` 读的是协调器
    /// 最新快照，复制出来的内容与屏幕一致。
    private func handleCopyTapped(messageID: String) {
        UIPasteboard.general.string = viewModel.displayText(for: messageID)
        Haptics.success()
    }

    // MARK: - 贴底

    /// 贴到最底部时 `contentOffset.y` 应该等于的值（可能为负——内容比可视区
    /// 矮时，"底部" 本来就在自然静止位置之上）。三处「最底部偏移」的计算
    /// 之前各写各的，容易改一处漏改另一处；这里收成一个计算属性，具体要不要
    /// 夹到 0 由各自调用方按语义决定（`stickToBottomIfNeeded` 允许贴到自然
    /// 负偏移的静止位；`handleScrollToBottom` 是用户主动点按钮，夹到 0；
    /// `distanceToBottom` 算的是「还差多少」，也要非负）。
    private var maxContentOffsetY: CGFloat {
        tableView.contentSize.height - tableView.bounds.height + tableView.adjustedContentInset.bottom
    }

    /// pinned 状态下贴底。一律无动画，避免与减速动画互相打断。
    private func stickToBottomIfNeeded() {
        guard autoScroll.shouldStickToBottom else { return }
        let bottomOffset = maxContentOffsetY
        guard bottomOffset > -tableView.adjustedContentInset.top else { return }

        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: bottomOffset), animated: false)
        autoScroll.endProgrammaticScroll()
    }

    /// 点"回到底部"：恢复贴底并带动画滚到底
    @objc private func handleScrollToBottom() {
        autoScroll.didTapScrollToBottom()
        autoScroll.beginProgrammaticScroll()
        tableView.setContentOffset(CGPoint(x: 0, y: max(0, maxContentOffsetY)), animated: true)
        // 动画结束前保持标记，避免中途被判成用户滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.autoScroll.endProgrammaticScroll()
        }
    }

    private var distanceToBottom: CGFloat {
        max(0, maxContentOffsetY - tableView.contentOffset.y)
    }

    // MARK: - 语音输入

    /// Critical 2：同步重入锁。`requestAuthorization()` 即便已经授权过，仍是一次
    /// 异步调用——await 期间 `recordingOverlay` 还没被赋值，如果只靠它做重入判断，
    /// 快速双击麦克风会让两个 Task 都通过检查，最终对同一个 `SystemSpeechTranscriber`
    /// 单例重复 `start()`，在同一条 audio bus 上装两次 tap，直接崩溃。
    /// `speechTask` 在这里跟 guard 处在同一个同步执行段里赋值，中间没有让出线程的
    /// 机会，第二次调用一定能看到非 nil 的 `speechTask` 而被挡在门外。
    private func startVoiceInput() {
        guard speechTask == nil else { return }

        speechTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runVoiceInputSession()
            self.speechTask = nil
        }
    }

    /// 一次完整的语音会话：授权 → 弹浮层 → 消费识别事件 → 收尾
    private func runVoiceInputSession() async {
        guard await transcriber.requestAuthorization() else {
            presentPermissionAlert()
            return
        }
        presentRecordingOverlay()
        transcribedText = ""

        do {
            for try await event in try transcriber.start() {
                switch event {
                case .partial(let text), .final(let text):
                    transcribedText = text
                    recordingOverlay?.setText(text)
                case .level(let value):
                    recordingOverlay?.update(level: value)
                }
            }
        } catch {
            // Critical 1：`recordingOverlay == nil` 说明用户已经点过「完成/取消」，
            // `finishVoiceInput` 已经跑过一次了——这次抛错只是 `transcriber.stop()`
            // 引发的收尾噪音（比如识别任务被 cancel），不是真的识别失败，
            // 不能再弹「语音识别失败，请重试」误导用户。
            guard recordingOverlay != nil else { return }
            finishVoiceInput(confirmed: false)
            presentErrorAlert("语音识别失败，请重试")
            return
        }

        // 流以「自然结束」（没有抛错）收尾。这里始终调用 `finishVoiceInput`，
        // 靠它自己的幂等 guard（`recordingOverlay != nil`）兜底：如果用户已经
        // 点过「完成」或「取消」，这次调用会直接 no-op；只有用户全程没点按钮、
        // 识别器自己给出终态结束的情况，才会在这里真正生效，补上唯一一次「确认」。
        finishVoiceInput(confirmed: true)
    }

    private func presentRecordingOverlay() {
        let overlay = RecordingOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        overlay.onCancel = { [weak self] in self?.finishVoiceInput(confirmed: false) }
        overlay.onConfirm = { [weak self] in self?.finishVoiceInput(confirmed: true) }
        recordingOverlay = overlay
        Haptics.light()
    }

    /// 识别结果写进输入框而**不直接发送**，用户可以先改再发。
    ///
    /// Critical 1：幂等保护。`recordingOverlay` 只有在「还没被处理过」时才非 nil，
    /// 用它做门槛——不管是用户点击「完成/取消」触发的，还是 `runVoiceInputSession`
    /// 里流自然收尾触发的，两条路径谁先到达都只有第一次真正生效，后到的直接 no-op，
    /// 不会重复拼接文字，也不会在「取消」之后又被自然收尾的分支误写。
    private func finishVoiceInput(confirmed: Bool) {
        guard recordingOverlay != nil else { return }
        // Important 4：取消飞行中的语音 Task，不留一个没有出口的悬挂任务。
        speechTask?.cancel()
        transcriber.stop()
        dismissRecordingOverlay()
        guard confirmed, !transcribedText.isEmpty else { return }
        let existing = inputBar.text
        inputBar.setText(existing.isEmpty ? transcribedText : existing + transcribedText)
    }

    private func dismissRecordingOverlay() {
        recordingOverlay?.removeFromSuperview()
        recordingOverlay = nil
    }

    private func presentPermissionAlert() {
        let alert = UIAlertController(
            title: "需要麦克风与语音识别权限",
            message: "请在「设置 → 隐私」中允许本 App 使用麦克风与语音识别",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func presentErrorAlert(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDelegate

extension ChatViewController: UITableViewDelegate {

    /// 优先读缓存，未命中再离屏测量
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard let messageID = dataSource.itemIdentifier(for: indexPath) else { return 0 }
        if let cached = heightCache[messageID] { return cached }

        guard let message = viewModel.state.messages.first(where: { $0.id == messageID }) else {
            return 0
        }
        let height = rowHeight(measureHeight(for: message, width: tableView.bounds.width), for: messageID)
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
                           reasoning: viewModel.displayReasoning(for: message.id),
                           status: message.status,
                           errorText: message.errorText,
                           pool: pool, cache: cache, renderer: renderer, measurer: measurer,
                           canCopy: !message.text.isEmpty,
                           trailingAction: trailingAction(for: message))
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
