import Foundation

/// 聊天页的业务编排。
///
/// **不 import UIKit**：属性串渲染是视图层的事，这里只产出纯模型。
///
/// 输出刻意分两类：
/// - `stateChanged` 表示消息条目的增删，交给 diffable data source
/// - `blocksPatched` 表示流式增量，绕开 data source 直接打到 cell 实例
///
/// 二者混用是流式聊天卡顿的主因，所以从接口层就把它们分开。
@MainActor
final class ChatViewModel {

    // MARK: - 对外类型

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
        var isStreaming: Bool = false
        var canSend: Bool = true
    }

    enum Output {
        case stateChanged(State)
        /// 该消息的块视图需要整体清空重建（例如 retry 重新起了一轮流）。
        /// 下游收到后应对相应 cell 的块视图调用 `setBlocks([])`，
        /// 避免新一轮内容被 `applyPatch` 追加到上一轮失败内容之后。
        case blocksReset(messageID: String)
        case blocksPatched(messageID: String, patch: BlockPatch)
        case reasoningUpdated(messageID: String, text: String)
        case streamFinished(messageID: String)
        case failed(ChatError, messageID: String?)
    }

    private(set) var state = State() {
        didSet {
            guard state != oldValue else { return }
            onOutput?(.stateChanged(state))
        }
    }

    var onOutput: ((Output) -> Void)?

    // MARK: - 依赖

    private let conversationID: String
    private let repository: ChatRepository
    private let providerFactory: () -> ChatProvider
    /// 与 `providerFactory` 同构：每次开一轮新流都现取一次，而不是在
    /// `init` 时把 `model`/`systemPrompt` 快照进 `let`。
    ///
    /// C1 修复：旧实现把这两个值存成 `let`，设置页换了服务商/模型后，
    /// 已经打开的聊天页（同一个 `ChatViewModel` 实例）拿到的还是旧值——
    /// `providerFactory` 闭包倒是会读到新的 baseURL/Key（新建的 adapter），
    /// 于是「新 provider + 旧 model 字段」拼出一个跨服务商的非法请求体。
    private let requestConfigProvider: () -> (model: String, systemPrompt: String?)
    private let throttle: StreamThrottling

    /// 上下文最多携带多少条历史
    private let contextLimit = 20

    // MARK: - 流式状态

    private var streamTask: Task<Void, Never>?
    private var streamingMessageID: String?
    private var splitter = StreamingBlockSplitter()

    /// 本帧攒下、还没交给切分器的增量
    private var pendingText = ""
    private var pendingReasoning = ""

    private var accumulatedText = ""
    private var accumulatedReasoning = ""
    private var usage: TokenUsage?

    /// 每条消息切好的块，供 cell 复用时重建
    private var blocksByMessage: [String: [MarkdownBlock]] = [:]

    private var isStopping = false

    // MARK: - 初始化

    init(conversationID: String,
         repository: ChatRepository,
         providerFactory: @escaping () -> ChatProvider,
         requestConfigProvider: @escaping () -> (model: String, systemPrompt: String?),
         throttle: StreamThrottling) {
        self.conversationID = conversationID
        self.repository = repository
        self.providerFactory = providerFactory
        self.requestConfigProvider = requestConfigProvider
        self.throttle = throttle

        throttle.onTick = { [weak self] in self?.flush() }
    }

    deinit {
        streamTask?.cancel()
        // CADisplayLink 强引用 target（DisplayLinkThrottle 自己），构成自环，
        // 唯有显式 invalidate() 才能打破；否则本 ViewModel 释放后 throttle
        // 仍会挂在主 RunLoop 上按帧空转，且间接经由 onOutput/onTick 闭包泄漏更多引用。
        throttle.stop()
    }

    // MARK: - 历史

    func loadHistory() {
        guard let records = try? repository.messages(in: conversationID) else { return }
        for record in records where record.role == .assistant {
            blocksByMessage[record.id] = Self.splitWhole(record.content)
        }
        state.messages = records.map(Self.viewData(from:))
    }

    func blocks(for messageID: String) -> [MarkdownBlock] {
        blocksByMessage[messageID] ?? []
    }

    /// Important 3：给「复制」这类不该看到中途空字符串的场景用的只读方法。
    /// `state.messages[...].text` 只在 `finishStream()` → `updateMessage()` 才回写,
    /// 流式期间 `send`/`retryLast` 把它重置为 `""`,中途增量只进 `blocksByMessage`,
    /// 不进 `state.messages[...].text`。这里命中当前正在流式的那条消息时改用
    /// `accumulatedText` 兜底——纯读,不写 `state`,不破坏「流式期间不写库」
    /// 与「stateChanged / blocksPatched 两条通路分开」这两条既有约束。
    func displayText(for messageID: String) -> String {
        if messageID == streamingMessageID {
            return accumulatedText
        }
        return state.messages.first(where: { $0.id == messageID })?.text ?? ""
    }

    // MARK: - 发送

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.canSend else { return }

        let now = Date().timeIntervalSince1970
        let baseOrdinal = state.messages.count

        let userRecord = MessageRecord(
            id: UUID().uuidString, conversationId: conversationID, ordinal: baseOrdinal,
            roleRaw: ChatRole.user.rawValue, content: trimmed, reasoning: nil,
            statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil, createdAt: now)

        let assistantRecord = MessageRecord(
            id: UUID().uuidString, conversationId: conversationID, ordinal: baseOrdinal + 1,
            roleRaw: ChatRole.assistant.rawValue, content: "", reasoning: nil,
            statusRaw: MessageStatus.streaming.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil, createdAt: now)

        try? repository.insertMessage(userRecord)
        try? repository.insertMessage(assistantRecord)
        try? repository.touchConversation(id: conversationID)

        // 把「插入两条消息」与「进入流式态」合并成一次赋值，
        // 避免一次 send() 调用触发多次 stateChanged
        var newState = state
        newState.messages.append(Self.viewData(from: userRecord))
        newState.messages.append(Self.viewData(from: assistantRecord))
        newState.isStreaming = true
        newState.canSend = false
        state = newState

        startStream(assistantID: assistantRecord.id)
    }

    func retryLast() {
        // 已有一条流在跑时不允许并发起第二条：否则旧 Task 仍会在后台
        // 继续 handle(chunk)，把内容写进被新流重置的 pendingText/accumulatedText/splitter，
        // 污染新流；且 stop() 只持有最新 streamTask 引用，旧任务会失去引用永远取消不掉。
        // 注意：这里不额外限制「只能对失败消息重试」——对已完成消息重新生成是有意支持的场景。
        guard !state.isStreaming, let last = state.messages.last, last.role == .assistant else { return }

        // 把失败/已完成的助手消息重置为流式占位后重新拉一次
        var newState = state
        newState.messages[newState.messages.count - 1] = MessageViewData(
            id: last.id, role: .assistant, text: "", reasoning: nil,
            status: .streaming, errorText: nil)
        newState.isStreaming = true
        newState.canSend = false

        blocksByMessage[last.id] = []
        state = newState

        // 显式告知下游：该消息的块视图需要整体清空重建。
        // 必须排在 startStream 之前——它会异步产出 blocksPatched，
        // 顺序颠倒会让下游先清空后收到的新内容
        onOutput?(.blocksReset(messageID: last.id))

        startStream(assistantID: last.id)
    }

    func stop() {
        guard state.isStreaming else { return }
        isStopping = true
        streamTask?.cancel()
    }

    // MARK: - 流式主流程

    private func startStream(assistantID: String) {
        // 覆盖变量前先取消已存在的流：否则旧 Task 会失去唯一引用，
        // 在后台继续跑并把内容写进被下面重置的缓冲区，污染新流
        streamTask?.cancel()

        streamingMessageID = assistantID
        splitter = StreamingBlockSplitter()
        pendingText = ""
        pendingReasoning = ""
        accumulatedText = ""
        accumulatedReasoning = ""
        usage = nil
        isStopping = false

        // isStreaming/canSend 已由调用方（send/retryLast）与各自的其他字段
        // 合并为一次 state 赋值，这里不再重复触发 stateChanged
        throttle.start()

        let request = makeRequest()
        let provider = providerFactory()

        streamTask = Task { [weak self] in
            do {
                for try await chunk in provider.stream(request) {
                    guard let self else { return }
                    // 偏离简报：原版先 `try Task.checkCancellation()` 再 `handle(chunk)`。
                    // 若 stop() 恰好与「已经到达但还没处理」的这个 chunk 竞速，
                    // 取消检查会先于处理抛出，导致这最后一个已经到手的增量被直接丢弃——
                    // 这与「stop 应保留已生成内容」的语义相悖，也是
                    // stopMarksStopped 测试间歇性失败的根因。调整为先处理、再判断是否继续，
                    // 保证任何已经从网络收到的增量都不会被取消检查吞掉。
                    self.handle(chunk)
                    try Task.checkCancellation()
                }
                self?.finishStream(error: nil)
            } catch {
                self?.finishStream(error: ChatError.from(error))
            }
        }
    }

    /// 只做累积，不触发任何 UI——出图统一交给节流器
    private func handle(_ chunk: StreamChunk) {
        switch chunk {
        case .textDelta(let text):
            pendingText += text
            accumulatedText += text
        case .reasoningDelta(let text):
            pendingReasoning += text
            accumulatedReasoning += text
        case .usage(let value):
            usage = value
        case .done:
            break
        }
    }

    /// 帧回调：把攒下的增量一次性推给 UI
    private func flush() {
        guard let messageID = streamingMessageID else { return }

        if !pendingText.isEmpty {
            let patch = splitter.append(pendingText)
            pendingText = ""
            blocksByMessage[messageID] = splitter.allBlocks
            if !patch.isEmpty {
                onOutput?(.blocksPatched(messageID: messageID, patch: patch))
            }
        }
        if !pendingReasoning.isEmpty {
            pendingReasoning = ""
            onOutput?(.reasoningUpdated(messageID: messageID, text: accumulatedReasoning))
        }
    }

    private func finishStream(error: ChatError?) {
        guard let messageID = streamingMessageID else { return }

        flush()
        let finalPatch = splitter.finish()
        blocksByMessage[messageID] = splitter.allBlocks
        if !finalPatch.newlySealed.isEmpty || finalPatch.open != nil {
            onOutput?(.blocksPatched(messageID: messageID, patch: finalPatch))
        }

        throttle.stop()
        streamTask = nil
        streamingMessageID = nil

        let status: MessageStatus
        var errorText: String?
        if let error {
            if case .cancelled = error {
                status = .stopped
            } else {
                status = .failed
                errorText = error.userMessage
            }
        } else {
            status = isStopping ? .stopped : .completed
        }

        // updateMessage 内部会把消息内容与 isStreaming/canSend 合并为一次 state 赋值
        updateMessage(id: messageID,
                      text: accumulatedText,
                      reasoning: accumulatedReasoning.isEmpty ? nil : accumulatedReasoning,
                      status: status,
                      errorText: errorText)

        if let error, status == .failed {
            onOutput?(.failed(error, messageID: messageID))
        } else {
            onOutput?(.streamFinished(messageID: messageID))
        }
    }

    // MARK: - 落库

    /// 只在流结束时写一次，避免高频写放大。
    /// 顺带把「消息内容更新」与「退出流式态」合并成一次 state 赋值——
    /// 这是 finishStream() 收尾时唯一的一次 stateChanged
    private func updateMessage(id: String, text: String, reasoning: String?,
                               status: MessageStatus, errorText: String?) {
        var newState = state
        if let index = newState.messages.firstIndex(where: { $0.id == id }) {
            newState.messages[index] = MessageViewData(id: id, role: .assistant, text: text,
                                                        reasoning: reasoning, status: status,
                                                        errorText: errorText)
        }
        newState.isStreaming = false
        newState.canSend = true
        state = newState

        guard var record = try? repository.messages(in: conversationID).first(where: { $0.id == id })
        else { return }
        record.content = text
        record.reasoning = reasoning
        record.statusRaw = status.rawValue
        record.errorMessage = errorText
        record.promptTokens = usage?.prompt
        record.completionTokens = usage?.completion
        try? repository.updateMessage(record)
        try? repository.touchConversation(id: conversationID)
    }

    // MARK: - 请求组装

    private func makeRequest() -> ChatRequest {
        // 只带最近若干轮，且排除正在生成的空占位
        let history = state.messages
            .filter { !($0.role == .assistant && $0.text.isEmpty) }
            .suffix(contextLimit)
            .map { ChatMessage(role: $0.role, content: $0.text) }

        // 现取而非用 init 时的快照：确保设置页刚改完就立刻生效（C1）。
        let config = requestConfigProvider()
        return ChatRequest(model: config.model,
                           messages: Array(history),
                           system: config.systemPrompt,
                           temperature: 0.7,
                           maxTokens: 4096)
    }

    // MARK: - 辅助

    private static func viewData(from record: MessageRecord) -> MessageViewData {
        MessageViewData(id: record.id, role: record.role, text: record.content,
                        reasoning: record.reasoning, status: record.status,
                        errorText: record.errorMessage)
    }

    private static func splitWhole(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text)
        _ = splitter.finish()
        return splitter.allBlocks
    }
}
