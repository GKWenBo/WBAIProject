import Foundation

/// 仅负责当前会话的展示订阅、Markdown 合帧及用户意图转发。
///
/// 数据流：协调器推 `.content` 时只记"有新内容"，真正的切块与输出由 display link
/// 每帧调用 `flush()` 完成，把高频网络增量合并到屏幕刷新节奏上。
@MainActor
final class ChatViewModel {
    /// 一条消息的展示数据
    struct MessageViewData: Equatable {
        let id: String
        let role: ChatRole
        let text: String
        let reasoning: String?
        let status: MessageStatus
        let errorText: String?
    }
    /// 页面整体状态
    struct State: Equatable {
        var messages: [MessageViewData] = []
        var isStreaming = false
        /// 生成中、准备中或有未保存内容时禁止发送
        var canSend = true
        var hasUnsavedContent = false
    }
    /// 推给 ViewController 的输出
    enum Output {
        /// 消息列表或状态变化，需要刷新列表
        case stateChanged(State)
        /// 重新生成：清空该消息已渲染的块
        case blocksReset(messageID: String)
        /// 流式增量：新闭合的块 + 当前未闭合块
        case blocksPatched(messageID: String, patch: BlockPatch)
        case reasoningUpdated(messageID: String, text: String)
        case streamFinished(messageID: String)
        case failed(ChatError, messageID: String?)
    }
    private(set) var state = State() {
        didSet { if state != oldValue { onOutput?(.stateChanged(state)) } }
    }
    var onOutput: ((Output) -> Void)?
    let conversationID: String
    private let coordinator: ChatGenerationCoordinator
    /// 合帧节流器，生成中才运行
    private let throttle: StreamThrottling
    /// 协调器订阅句柄，页面不可见时注销
    private var observation: UUID?
    /// 后台期间丢弃了事件，回前台时需要整体重载
    private var suspendedForBackground = false
    /// 正在生成的那条消息的增量切块器
    private var splitter = StreamingBlockSplitter()
    /// 已交给切块器的正文，用来算出下一帧的增量
    private var renderedText = ""
    /// 已推给页面的思考内容
    private var renderedReasoning = ""
    /// 消息 id → 切好的块，供 cell 配置时读取
    private var blocksByMessage: [String: [MarkdownBlock]] = [:]

    init(conversationID: String, coordinator: ChatGenerationCoordinator, throttle: StreamThrottling) {
        self.conversationID = conversationID
        self.coordinator = coordinator
        self.throttle = throttle
        throttle.onTick = { [weak self] in self?.flush() }
        observe()
    }

    /// 自建协调器的便利构造，主要供测试使用
    convenience init(conversationID: String, repository: ChatRepository,
                     providerFactory: @escaping () -> ChatProvider,
                     requestConfigProvider: @escaping () -> (model: String, systemPrompt: String?),
                     throttle: StreamThrottling) {
        self.init(conversationID: conversationID,
                  coordinator: ChatGenerationCoordinator(repository: repository,
                    providerFactory: providerFactory, configProvider: requestConfigProvider), throttle: throttle)
    }

    deinit {
        throttle.stop()
        if let observation {
            let id = conversationID
            let owner = coordinator
            Task { @MainActor in owner.removeObserver(conversationID: id, id: observation) }
        }
    }

    /// 输入草稿，存在协调器里，切换会话后仍保留
    var draft: String {
        get { coordinator.draft(for: conversationID) }
        set { coordinator.setDraft(newValue, for: conversationID) }
    }
    var readingPosition: ChatGenerationCoordinator.ReadingPosition {
        get { coordinator.readingPosition(for: conversationID) }
        set { coordinator.setReadingPosition(newValue, for: conversationID) }
    }

    /// 页面可见时订阅并重载，不可见时退订、停止合帧（生成本身不受影响）
    func setVisible(_ visible: Bool) {
        if visible { observe(); loadHistory() }
        else {
            if let observation { coordinator.removeObserver(conversationID: conversationID, id: observation) }
            observation = nil
            throttle.stop()
        }
    }
    private func observe() {
        guard observation == nil else { return }
        observation = coordinator.observe(conversationID: conversationID) { [weak self] event in
            guard let self else { return }
            if self.coordinator.isInBackground {
                self.suspendedForBackground = true
                self.throttle.stop()
                return
            }
            if self.suspendedForBackground {
                self.suspendedForBackground = false
                self.loadHistory()
            }
            switch event {
            case .state: self.refreshState()
            case .content: break // 网络只更新快照，排版由 display link 合帧。
            case .replacement:
                self.splitter = StreamingBlockSplitter()
                self.renderedText = ""; self.renderedReasoning = ""
                if let id = self.state.messages.last?.id {
                    self.blocksByMessage[id] = []
                    self.onOutput?(.blocksReset(messageID: id))
                    self.onOutput?(.reasoningUpdated(messageID: id, text: ""))
                }
            case .error(let error): self.onOutput?(.failed(error, messageID: nil))
            }
        }
    }

    /// 全量加载：历史消息一次性切块，正在生成的消息重建切块器
    func loadHistory() {
        do {
            let snapshot = try coordinator.snapshot(conversationID: conversationID)
            blocksByMessage.removeAll()
            for record in snapshot.messages where record.role == .assistant {
                blocksByMessage[record.id] = Self.splitWhole(record.content)
            }
            resetSplitter(snapshot)
            apply(snapshot)
        } catch { onOutput?(.failed(.storage, messageID: nil)) }
    }
    func blocks(for messageID: String) -> [MarkdownBlock] { blocksByMessage[messageID] ?? [] }
    func displayText(for messageID: String) -> String {
        (try? coordinator.snapshot(conversationID: conversationID).messages.first { $0.id == messageID }?.content) ?? ""
    }
    func displayReasoning(for messageID: String) -> String? {
        try? coordinator.snapshot(conversationID: conversationID).messages.first { $0.id == messageID }?.reasoning
    }
    @discardableResult
    func send(_ text: String) async -> Bool {
        await coordinator.send(conversationID: conversationID, text: text)
    }
    /// 重新生成最后一条助手回复
    @discardableResult
    func retryLast() async -> Bool {
        guard let last = state.messages.last, last.role == .assistant else { return false }
        return await coordinator.regenerate(conversationID: conversationID, messageID: last.id)
    }
    func stop() { coordinator.stop(conversationID: conversationID) }
    func retrySave() async -> Bool { await coordinator.retrySave(conversationID: conversationID) }

    /// 处理状态事件：先冲刷剩余增量，再更新状态；生成刚结束时补发完成/失败输出
    private func refreshState() {
        guard let snapshot = try? coordinator.snapshot(conversationID: conversationID) else {
            onOutput?(.failed(.storage, messageID: nil)); return
        }
        let wasStreaming = state.isStreaming
        flush()
        if state.messages.last?.id != snapshot.messages.last?.id {
            resetSplitter(snapshot)
        }
        if !snapshot.isStreaming, let last = snapshot.messages.last, last.role == .assistant {
            blocksByMessage[last.id] = Self.splitWhole(last.content)
        }
        apply(snapshot)
        if wasStreaming && !snapshot.isStreaming, let last = snapshot.messages.last {
            if last.status == .failed || last.status == .interrupted {
                onOutput?(.failed(snapshot.error ?? (last.endReason == "storageFailure" ? .storage : .interruptedStream), messageID: last.id))
            } else { onOutput?(.streamFinished(messageID: last.id)) }
        }
    }

    /// 快照 → State，并按是否在生成启停合帧
    private func apply(_ snapshot: ChatGenerationCoordinator.Snapshot) {
        state = State(messages: snapshot.messages.map {
            MessageViewData(id: $0.id, role: $0.role, text: $0.content, reasoning: $0.reasoning,
                            status: $0.status, errorText: $0.errorMessage)
        }, isStreaming: snapshot.isStreaming,
           canSend: !snapshot.isStreaming && !snapshot.isPreparing && !snapshot.hasUnsavedContent,
           hasUnsavedContent: snapshot.hasUnsavedContent)
        if snapshot.isStreaming && !coordinator.isInBackground && observation != nil { throttle.start() }
        else { throttle.stop() }
    }
    /// 用最后一条助手消息的当前内容重建切块器
    private func resetSplitter(_ snapshot: ChatGenerationCoordinator.Snapshot) {
        splitter = StreamingBlockSplitter()
        renderedText = snapshot.messages.last?.role == .assistant ? snapshot.messages.last?.content ?? "" : ""
        renderedReasoning = snapshot.messages.last?.reasoning ?? ""
        _ = splitter.append(renderedText)
        if let last = snapshot.messages.last, last.role == .assistant { blocksByMessage[last.id] = splitter.allBlocks }
    }
    /// 每帧调用：把上一帧之后新增的正文喂给切块器并输出 patch。
    /// 内容不再以已渲染文本为前缀（如被替换）时整体重建
    private func flush() {
        guard let snapshot = try? coordinator.snapshot(conversationID: conversationID),
              let last = snapshot.messages.last, last.role == .assistant else { return }
        if !last.content.hasPrefix(renderedText) { resetSplitter(snapshot) }
        if last.content != renderedText {
            let delta = String(last.content.dropFirst(renderedText.count))
            renderedText = last.content
            let patch = splitter.append(delta)
            blocksByMessage[last.id] = splitter.allBlocks
            if !patch.isEmpty { onOutput?(.blocksPatched(messageID: last.id, patch: patch)) }
        }
        if (last.reasoning ?? "") != renderedReasoning {
            renderedReasoning = last.reasoning ?? ""
            onOutput?(.reasoningUpdated(messageID: last.id, text: renderedReasoning))
        }
    }
    /// 一次性切完整段文本（全部闭合）
    private static func splitWhole(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text); _ = splitter.finish()
        return splitter.allBlocks
    }
}
