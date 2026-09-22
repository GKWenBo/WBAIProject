import Foundation
import OSLog

/// 页面只订阅会话；生成任务、正文快照和保存由应用持有。
@MainActor
final class ChatGenerationCoordinator {
    enum Event { case state, content, replacement, error(ChatError) }
    struct Snapshot {
        var messages: [MessageRecord]
        var isStreaming: Bool
        var isPreparing: Bool
        var hasUnsavedContent: Bool
        var error: ChatError?
    }
    struct ReadingPosition {
        var offset: Double = 0
        var pinned = true
    }
    private final class Session {
        var messages: [MessageRecord]
        let generationID: String
        let startedAt = ContinuousClock.now
        var task: Task<Void, Never>?
        var checkpointTask: Task<Void, Never>?
        var running = true
        var dirty = false
        var replaced = false
        var sawDone = false
        var unsaved = false
        var pendingSaves = 0
        var saveWaiters: [CheckedContinuation<Void, Never>] = []
        var finishReason: String?
        var error: ChatError?
        init(messages: [MessageRecord], generationID: String) {
            self.messages = messages
            self.generationID = generationID
        }
        var reply: MessageRecord {
            get { messages[messages.count - 1] }
            set { messages[messages.count - 1] = newValue }
        }
        deinit { task?.cancel(); checkpointTask?.cancel() }
    }

    private let repository: ChatRepository
    private let store: GenerationStore
    private let providerFactory: () -> ChatProvider
    private let configProvider: () -> (model: String, systemPrompt: String?)
    private let clock: GenerationClock
    private let background: BackgroundExecution?
    private let limit: Int
    private let checkpointInterval: TimeInterval
    private let backgroundLimit: TimeInterval
    private var sessions: [String: Session] = [:]
    private var preparing: [String: String] = [:]
    private var deleting: Set<String> = []
    private var expiredPreparing: Set<String> = []
    private var backgroundEpoch = 0
    private var observers: [String: [UUID: (Event) -> Void]] = [:]
    private var activityObservers: [UUID: () -> Void] = [:]
    private var backgroundTimer: Task<Void, Never>?
    private(set) var isInBackground = false
    private var drafts: [String: String] = [:]
    private var positions: [String: ReadingPosition] = [:]
    private let logger = Logger(subsystem: "WBChatApp", category: "Generation")

    init(repository: ChatRepository,
         providerFactory: @escaping () -> ChatProvider,
         configProvider: @escaping () -> (model: String, systemPrompt: String?),
         clock: GenerationClock = SystemGenerationClock(),
         background: BackgroundExecution? = nil,
         limit: Int = 3, checkpointInterval: TimeInterval = 1, backgroundLimit: TimeInterval = 20) {
        self.repository = repository
        self.store = GenerationStore(repository: repository)
        self.providerFactory = providerFactory
        self.configProvider = configProvider
        self.clock = clock
        self.background = background
        self.limit = limit
        self.checkpointInterval = checkpointInterval
        self.backgroundLimit = backgroundLimit
    }

    deinit { backgroundTimer?.cancel() }

    func snapshot(conversationID: String) throws -> Snapshot {
        let session = sessions[conversationID]
        return Snapshot(messages: try session?.messages ?? repository.messages(in: conversationID),
                        isStreaming: session?.running == true,
                        isPreparing: preparing[conversationID] != nil,
                        hasUnsavedContent: session?.unsaved == true, error: session?.error)
    }

    func observe(conversationID: String, _ callback: @escaping (Event) -> Void) -> UUID {
        let id = UUID()
        observers[conversationID, default: [:]][id] = callback
        return id
    }
    func removeObserver(conversationID: String, id: UUID) { observers[conversationID]?[id] = nil }
    func observeActivity(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID(); activityObservers[id] = callback; return id
    }
    func removeActivityObserver(_ id: UUID) { activityObservers[id] = nil }
    func isGenerating(_ id: String) -> Bool { sessions[id]?.running == true || preparing[id] != nil }
    func draft(for id: String) -> String { drafts[id] ?? "" }
    func setDraft(_ text: String, for id: String) { drafts[id] = text }
    func readingPosition(for id: String) -> ReadingPosition { positions[id] ?? ReadingPosition() }
    func setReadingPosition(_ value: ReadingPosition, for id: String) { positions[id] = value }

    @discardableResult
    func send(conversationID: String, text: String) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return await begin(conversationID: conversationID, retryID: nil, text: text)
    }
    @discardableResult
    func regenerate(conversationID: String, messageID: String) async -> Bool {
        guard let last = try? snapshot(conversationID: conversationID).messages.last,
              last.id == messageID, last.role == .assistant else { return false }
        return await begin(conversationID: conversationID, retryID: messageID, text: "")
    }

    private func begin(conversationID: String, retryID: String?, text: String) async -> Bool {
        guard !deleting.contains(conversationID), !isGenerating(conversationID), sessions[conversationID]?.unsaved != true else { return false }
        guard sessions.values.filter(\.running).count + preparing.count < limit else {
            notify(conversationID, .error(.generationLimit)); return false
        }
        guard !isInBackground else {
            logger.info("generation rejected while backgrounded")
            return false
        }
        let generationID = UUID().uuidString
        let config = configProvider()
        let provider = providerFactory()
        preparing[conversationID] = generationID
        notify(conversationID, .state)
        activityChanged()
        ensureBackgroundProtection()
        do {
            // 先保留准备名额，避免等待期间第二次点击也开始事务。
            if let previous = sessions[conversationID], previous.pendingSaves > 0 {
                await withCheckedContinuation { previous.saveWaiters.append($0) }
                guard preparing[conversationID] == generationID else { return false }
                guard !previous.unsaved else { throw ChatError.storage }
            }
            let records = try await store.perform { repository in
                if let retryID {
                    return try repository.beginRegeneration(conversationID: conversationID, messageID: retryID, generationID: generationID)
                }
                return try repository.beginTurn(conversationID: conversationID, text: text, generationID: generationID)
            }
            guard preparing[conversationID] == generationID else { return false }
            preparing[conversationID] = nil
            let session = Session(messages: records, generationID: generationID)
            sessions[conversationID] = session
            if retryID == nil, drafts[conversationID]?.trimmingCharacters(in: .whitespacesAndNewlines) == text { drafts[conversationID] = "" }
            let history = records.dropLast().filter { $0.role != .assistant || $0.status == .completed }
                .suffix(20).map { ChatMessage(role: $0.role, content: $0.content) }
            let request = ChatRequest(model: config.model, messages: history, system: config.systemPrompt,
                                      temperature: 0.7, maxTokens: 4096)
            notify(conversationID, .state)
            activityChanged()
            if expiredPreparing.remove(generationID) != nil {
                finish(conversationID, status: .interrupted, reason: "backgroundExpired")
                return true
            }
            ensureBackgroundProtection()
            guard session.running else { return true }
            session.checkpointTask = Task { [weak self, clock, checkpointInterval] in
                while !Task.isCancelled {
                    do { try await clock.sleep(seconds: checkpointInterval) } catch { return }
                    guard let self, self.isCurrent(conversationID, generationID) else { return }
                    self.persist(conversationID)
                }
            }
            session.task = Task { [weak self] in
                do {
                    for try await chunk in provider.stream(request) {
                        guard !Task.isCancelled, let self, self.isCurrent(conversationID, generationID) else { return }
                        self.consume(chunk, conversationID: conversationID)
                    }
                    guard let self, self.isCurrent(conversationID, generationID) else { return }
                    if self.sessions[conversationID]?.sawDone == true {
                        self.finish(conversationID, status: .completed, reason: "completed")
                    } else {
                        self.finish(conversationID, status: .interrupted, reason: "unexpectedEOF", error: .interruptedStream)
                    }
                } catch {
                    guard let self, self.isCurrent(conversationID, generationID) else { return }
                    let error = ChatError.from(error)
                    let interrupted: Bool
                    switch error {
                    case .network, .timeout, .interruptedStream, .cancelled: interrupted = true
                    default: interrupted = false
                    }
                    self.finish(conversationID, status: interrupted ? .interrupted : .failed,
                                reason: interrupted ? "connectionInterrupted" : "requestFailed", error: error)
                }
            }
            // 持久化开始期间可能切入后台：新的任务同样受剩余后台预算约束。
            if isInBackground { startBackgroundTimer() }
            return true
        } catch {
            guard preparing[conversationID] == generationID else { return false }
            preparing[conversationID] = nil
            expiredPreparing.remove(generationID)
            releaseBackgroundIfIdle()
            logger.error("begin transaction failed")
            notify(conversationID, .state)
            notify(conversationID, .error(.storage))
            activityChanged()
            return false
        }
    }

    private func isCurrent(_ conversationID: String, _ generationID: String) -> Bool {
        sessions[conversationID]?.generationID == generationID && sessions[conversationID]?.running == true
    }

    private func consume(_ chunk: StreamChunk, conversationID: String) {
        guard let session = sessions[conversationID] else { return }
        switch chunk {
        case .textDelta(let text), .reasoningDelta(let text):
            guard !text.isEmpty else { return }
            if !session.replaced {
                session.replaced = true
                session.reply.content = ""
                session.reply.reasoning = nil
                session.reply.promptTokens = nil
                session.reply.completionTokens = nil
                notify(conversationID, .replacement)
            }
            if case .textDelta = chunk { session.reply.content += text }
            else { session.reply.reasoning = (session.reply.reasoning ?? "") + text }
            session.dirty = true
            notify(conversationID, .content)
        case .usage(let usage):
            session.reply.promptTokens = usage.prompt
            session.reply.completionTokens = usage.completion
            session.dirty = true
        case .done(let reason):
            session.sawDone = true
            session.finishReason = reason
        case .finishReason(let reason):
            session.finishReason = reason
        }
    }

    func stop(conversationID: String) {
        guard sessions[conversationID]?.running == true else { return }
        finish(conversationID, status: .stopped, reason: "userStopped")
    }

    private func finish(_ id: String, status: MessageStatus, reason: String, error: ChatError? = nil) {
        guard let session = sessions[id], session.running else { return }
        session.running = false // 先关闭事件入口，再取消网络；不等待取消回调。
        session.task?.cancel(); session.task = nil
        session.checkpointTask?.cancel(); session.checkpointTask = nil
        session.reply.statusRaw = status.rawValue
        session.reply.endReason = status == .completed ? (session.finishReason ?? reason) : reason
        session.error = error
        session.reply.errorMessage = error?.userMessage
        if status == .stopped { session.reply.errorMessage = "已停止生成" }
        if reason == "backgroundExpired" { session.reply.errorMessage = "后台运行时间已结束，回复未完成" }
        if status == .completed {
            switch session.finishReason {
            case "length", "max_tokens": session.reply.errorMessage = "已达到输出长度限制，回复可能未完整"
            case "content_filter", "refusal": session.reply.errorMessage = "回复受到内容限制"
            default: break
            }
        }
        session.dirty = true
        persist(id)
        notify(id, .state)
        activityChanged()
        releaseBackgroundIfIdle()
        let elapsed = session.startedAt.duration(to: .now).components
        logger.info("generation ended: \(reason, privacy: .public), elapsed seconds: \(elapsed.seconds)")
    }

    private func persist(_ id: String) {
        guard let session = sessions[id], session.dirty else { return }
        session.dirty = false
        session.reply.snapshotSequence += 1
        session.reply.checkpointAt = Date().timeIntervalSince1970
        let record = session.reply
        session.pendingSaves += 1
        store.schedule({ try $0.saveGeneration(record) }) { [weak self] result in
            Task { @MainActor [weak self] in
                defer {
                    session.pendingSaves -= 1
                    if session.pendingSaves == 0 {
                        let waiters = session.saveWaiters
                        session.saveWaiters.removeAll()
                        for waiter in waiters { waiter.resume() }
                    }
                }
                guard let self, let current = self.sessions[id], current.generationID == record.generationID else { return }
                if case .failure = result, current.reply.snapshotSequence == record.snapshotSequence {
                    self.logger.error("generation checkpoint failed")
                    current.running = false
                    current.task?.cancel(); current.task = nil
                    current.checkpointTask?.cancel(); current.checkpointTask = nil
                    current.unsaved = true
                    current.reply.statusRaw = MessageStatus.interrupted.rawValue
                    current.reply.endReason = "storageFailure"
                    current.reply.errorMessage = ChatError.storage.userMessage
                    self.notify(id, .state)
                    self.activityChanged()
                    self.releaseBackgroundIfIdle()
                }
            }
        }
    }

    func retrySave(conversationID: String) async -> Bool {
        guard let session = sessions[conversationID], session.unsaved else { return true }
        session.reply.snapshotSequence += 1
        session.reply.checkpointAt = Date().timeIntervalSince1970
        var record = session.reply
        record.errorMessage = "生成已中断，可重新生成"
        do {
            let saved = try await store.perform { try $0.saveGeneration(record) }
            guard sessions[conversationID] === session, saved else { return false }
            session.unsaved = false
            session.reply = record
            notify(conversationID, .state)
            return true
        } catch { notify(conversationID, .error(.storage)); return false }
    }

    func deleteConversation(_ id: String) async throws {
        guard deleting.insert(id).inserted else { return }
        defer { deleting.remove(id) }
        if let pending = preparing.removeValue(forKey: id) { expiredPreparing.remove(pending) }
        let session = sessions.removeValue(forKey: id)
        session?.task?.cancel(); session?.checkpointTask?.cancel()
        activityChanged(); releaseBackgroundIfIdle()
        do {
            try await store.perform { try $0.deleteConversation(id: id) }
            drafts[id] = nil; positions[id] = nil
            notify(id, .state)
        } catch {
            // begin 事务可能已提交，但被删除意图作废；删除失败仍须收尾该占位。
            let records = try? await store.perform { try $0.messages(in: id) }
            let recoverable: Session?
            if let records, let last = records.last, last.status == .streaming, let generationID = last.generationID {
                recoverable = session?.generationID == generationID
                    ? session : Session(messages: records, generationID: generationID)
            } else { recoverable = session }
            if let session = recoverable {
                sessions[id] = session
                if session.running {
                    finish(id, status: .interrupted, reason: "deleteFailed", error: .storage)
                } else { notify(id, .state) }
            }
            throw error
        }
    }

    func enterBackground() {
        guard !isInBackground else { return }
        isInBackground = true
        for id in Array(sessions.keys) { persist(id); notify(id, .state) }
        ensureBackgroundProtection()
        startBackgroundTimer()
    }
    func enterForeground() {
        isInBackground = false
        backgroundEpoch += 1
        backgroundTimer?.cancel(); backgroundTimer = nil
        for id in Array(observers.keys) { notify(id, .state) }
        ensureBackgroundProtection()
    }
    private func ensureBackgroundProtection() {
        guard sessions.values.contains(where: \.running) || !preparing.isEmpty, let background else { return }
        if !background.begin(expiration: { [weak self] in self?.expireBackground() }) {
            expireBackground()
        }
    }
    private func startBackgroundTimer() {
        guard backgroundTimer == nil, sessions.values.contains(where: \.running) || !preparing.isEmpty else { return }
        let epoch = backgroundEpoch
        backgroundTimer = Task { [weak self, clock, backgroundLimit] in
            do { try await clock.sleep(seconds: backgroundLimit) } catch { return }
            guard let self, !Task.isCancelled, self.isInBackground, self.backgroundEpoch == epoch else { return }
            self.expireBackground()
        }
    }
    func expireBackground() {
        expiredPreparing.formUnion(preparing.values)
        backgroundTimer?.cancel(); backgroundTimer = nil
        for (id, session) in sessions where session.running {
            finish(id, status: .interrupted, reason: "backgroundExpired")
        }
        background?.end()
    }
    private func releaseBackgroundIfIdle() {
        guard !sessions.values.contains(where: \.running), preparing.isEmpty else { return }
        backgroundTimer?.cancel(); backgroundTimer = nil
        background?.end()
    }
    private func notify(_ id: String, _ event: Event) {
        for callback in Array(observers[id, default: [:]].values) { callback(event) }
    }
    private func activityChanged() { for callback in Array(activityObservers.values) { callback() } }
}
