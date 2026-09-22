import Foundation

/// 仅负责当前会话的展示订阅、Markdown 合帧及用户意图转发。
@MainActor
final class ChatViewModel {
    struct MessageViewData: Equatable {
        let id: String
        let role: ChatRole
        let text: String
        let reasoning: String?
        let status: MessageStatus
        let errorText: String?
    }
    struct State: Equatable {
        var messages: [MessageViewData] = []
        var isStreaming = false
        var canSend = true
        var hasUnsavedContent = false
    }
    enum Output {
        case stateChanged(State)
        case blocksReset(messageID: String)
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
    private let throttle: StreamThrottling
    private var observation: UUID?
    private var suspendedForBackground = false
    private var splitter = StreamingBlockSplitter()
    private var renderedText = ""
    private var renderedReasoning = ""
    private var blocksByMessage: [String: [MarkdownBlock]] = [:]

    init(conversationID: String, coordinator: ChatGenerationCoordinator, throttle: StreamThrottling) {
        self.conversationID = conversationID
        self.coordinator = coordinator
        self.throttle = throttle
        throttle.onTick = { [weak self] in self?.flush() }
        observe()
    }

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

    var draft: String {
        get { coordinator.draft(for: conversationID) }
        set { coordinator.setDraft(newValue, for: conversationID) }
    }
    var readingPosition: ChatGenerationCoordinator.ReadingPosition {
        get { coordinator.readingPosition(for: conversationID) }
        set { coordinator.setReadingPosition(newValue, for: conversationID) }
    }

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
    @discardableResult
    func retryLast() async -> Bool {
        guard let last = state.messages.last, last.role == .assistant else { return false }
        return await coordinator.regenerate(conversationID: conversationID, messageID: last.id)
    }
    func stop() { coordinator.stop(conversationID: conversationID) }
    func retrySave() async -> Bool { await coordinator.retrySave(conversationID: conversationID) }

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
    private func resetSplitter(_ snapshot: ChatGenerationCoordinator.Snapshot) {
        splitter = StreamingBlockSplitter()
        renderedText = snapshot.messages.last?.role == .assistant ? snapshot.messages.last?.content ?? "" : ""
        renderedReasoning = snapshot.messages.last?.reasoning ?? ""
        _ = splitter.append(renderedText)
        if let last = snapshot.messages.last, last.role == .assistant { blocksByMessage[last.id] = splitter.allBlocks }
    }
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
    private static func splitWhole(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text); _ = splitter.finish()
        return splitter.allBlocks
    }
}
