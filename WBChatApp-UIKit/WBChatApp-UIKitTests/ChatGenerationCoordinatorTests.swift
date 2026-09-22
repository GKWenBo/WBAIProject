import Foundation
import Testing
import GRDB
@testable import WBChatApp_UIKit

@MainActor
private final class TestBackgroundExecution: BackgroundExecution {
    var available = true
    var expiration: (@MainActor () -> Void)?
    var active = false
    func begin(expiration: @escaping @MainActor () -> Void) -> Bool {
        self.expiration = expiration
        active = available
        return available
    }
    func end() { active = false }
}

/// 可直接投递迟到事件的真实 AsyncThrowingStream；故意不因取消停止生产。
private final class ControlledGenerationProvider: ChatProvider, @unchecked Sendable {
    let streamValue: AsyncThrowingStream<StreamChunk, Error>
    let continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation
    private(set) var request: ChatRequest?
    init() {
        var continuation: AsyncThrowingStream<StreamChunk, Error>.Continuation!
        streamValue = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        self.request = request
        return streamValue
    }
}

@Suite("生成生命周期")
@MainActor
struct ChatGenerationCoordinatorTests {
    private func waitUntil(_ condition: () throws -> Bool) async throws {
        for _ in 0..<200 {
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try condition(), "异步状态必须在限定时间内完成")
    }
    private func makeRepository() throws -> GRDBChatRepository {
        GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
    }
    private func conversation(_ repository: GRDBChatRepository) throws -> String {
        try repository.createConversation(title: "test", provider: .deepSeek, model: "test").id
    }

    @Test("切换页面后任务继续，停止立即恢复输入并拒绝迟到增量")
    func survivesViewModelReleaseAndIgnoresLateEvents() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: { provider }, configProvider: { ("test", nil) })
        var page: ChatViewModel? = ChatViewModel(conversationID: id, coordinator: coordinator, throttle: ManualThrottle())
        #expect(await page!.send("hi"))
        page = nil
        provider.continuation.yield(.textDelta("保留"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.content == "保留" }
        coordinator.stop(conversationID: id)
        #expect(!coordinator.isGenerating(id))
        provider.continuation.yield(.textDelta("迟到"))
        provider.continuation.finish()
        try await waitUntil { try repository.messages(in: id).last?.status == .stopped }
        #expect(try repository.messages(in: id).last?.content == "保留")
    }

    @Test("首段前重试失败保留旧内容，下一次首段整体替换")
    func regenerationPreservesUntilFirstDelta() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        var providers: [ControlledGenerationProvider] = []
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            let provider = ControlledGenerationProvider(); providers.append(provider); return provider
        }, configProvider: { ("test", nil) })
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        providers[0].continuation.yield(.textDelta("旧正文"))
        providers[0].continuation.yield(.reasoningDelta("旧思考"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.reasoning == "旧思考" }
        coordinator.stop(conversationID: id)
        let messageID = try #require(coordinator.snapshot(conversationID: id).messages.last?.id)
        #expect(await coordinator.regenerate(conversationID: id, messageID: messageID))
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.content == "旧正文")
        providers[1].continuation.finish(throwing: URLError(.notConnectedToInternet))
        try await waitUntil { !coordinator.isGenerating(id) }
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.content == "旧正文")
        #expect(await coordinator.regenerate(conversationID: id, messageID: messageID))
        providers[2].continuation.yield(.reasoningDelta("新思考"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.reasoning == "新思考" }
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.content == "")
        coordinator.stop(conversationID: id)
    }

    @Test("全局限流不新增消息、不清空草稿，删除后晚到事件不复活会话")
    func capacityAndDelete() async throws {
        let repository = try makeRepository()
        let ids = try (0..<4).map { _ in try conversation(repository) }
        var providers: [ControlledGenerationProvider] = []
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            let provider = ControlledGenerationProvider(); providers.append(provider); return provider
        }, configProvider: { ("test", nil) })
        for id in ids.prefix(3) { #expect(await coordinator.send(conversationID: id, text: "hi")) }
        coordinator.setDraft("未发送", for: ids[3])
        #expect(await coordinator.send(conversationID: ids[3], text: "未发送") == false)
        #expect(try repository.messages(in: ids[3]).isEmpty)
        #expect(coordinator.draft(for: ids[3]) == "未发送")
        try await coordinator.deleteConversation(ids[0])
        providers[0].continuation.yield(.textDelta("迟到")); providers[0].continuation.finish()
        #expect(try repository.messages(in: ids[0]).isEmpty)
        #expect(await coordinator.send(conversationID: ids[3], text: "未发送"))
        for id in ids.dropFirst() { coordinator.stop(conversationID: id) }
    }

    @Test("后台到期保存内容并停止，回前台不重发")
    func backgroundExpiration() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let background = TestBackgroundExecution()
        var requestCount = 0
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            requestCount += 1; return provider
        }, configProvider: { ("test", nil) }, background: background)
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        provider.continuation.yield(.textDelta("后台正文"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.content == "后台正文" }
        coordinator.enterBackground()
        background.expiration?()
        #expect(!coordinator.isGenerating(id))
        #expect(!background.active)
        coordinator.enterForeground()
        #expect(requestCount == 1)
        try await waitUntil { try repository.messages(in: id).last?.status == .interrupted }
        #expect(try repository.messages(in: id).last?.content == "后台正文")
        #expect(try repository.messages(in: id).last?.endReason == "backgroundExpired")
    }

    @Test("周期快照不依赖界面刷新；冷启动恢复磁盘内容")
    func checkpointAndRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: url))
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        var coordinator: ChatGenerationCoordinator? = ChatGenerationCoordinator(repository: repository, providerFactory: { provider },
            configProvider: { ("test", nil) }, checkpointInterval: 0.02)
        #expect(await coordinator!.send(conversationID: id, text: "hi"))
        provider.continuation.yield(.textDelta("磁盘正文"))
        try await waitUntil { try repository.messages(in: id).last?.content == "磁盘正文" }
        coordinator = nil // 没有正常结束或生命周期回调。
        let reopened = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: url))
        try reopened.recoverInterruptedGenerations()
        #expect(try reopened.messages(in: id).last?.content == "磁盘正文")
        #expect(try reopened.messages(in: id).last?.status == .interrupted)
    }

    @Test("未完成助手内容不进入下一次请求上下文")
    func excludesPartialAssistantFromContext() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        var providers: [ControlledGenerationProvider] = []
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            let provider = ControlledGenerationProvider(); providers.append(provider); return provider
        }, configProvider: { ("test", nil) })
        #expect(await coordinator.send(conversationID: id, text: "第一问"))
        providers[0].continuation.yield(.textDelta("不完整"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.content == "不完整" }
        coordinator.stop(conversationID: id)
        #expect(await coordinator.send(conversationID: id, text: "第二问"))
        try await waitUntil { providers[1].request != nil }
        #expect(providers[1].request?.messages.map(\.content) == ["第一问", "第二问"])
        coordinator.stop(conversationID: id)
    }
    @Test("保存失败停止生成并保留内存正文，重试保存恢复持久化")
    func storageFailureCanBeRetried() async throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        let repository = GRDBChatRepository(queue: queue)
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: { provider },
            configProvider: { ("test", nil) }, checkpointInterval: 0.02)
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_snapshot BEFORE UPDATE ON message BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
        }
        provider.continuation.yield(.textDelta("不能丢失"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).hasUnsavedContent }
        #expect(!coordinator.isGenerating(id))
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.content == "不能丢失")
        try await queue.write { try $0.execute(sql: "DROP TRIGGER reject_snapshot") }
        #expect(await coordinator.retrySave(conversationID: id))
        #expect(try repository.messages(in: id).last?.content == "不能丢失")
        #expect(try !coordinator.snapshot(conversationID: id).hasUnsavedContent)
    }

    @Test("后台申请失败立即中断，不能发起网络请求")
    func unavailableBackgroundProtection() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let background = TestBackgroundExecution()
        background.available = false
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: { provider },
            configProvider: { ("test", nil) }, background: background)
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        #expect(!coordinator.isGenerating(id))
        #expect(provider.request == nil)
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.status == .interrupted)
    }

}

private actor ManualGenerationClock: GenerationClock {
    private var now: TimeInterval = 0
    private var waiters: [UUID: (TimeInterval, CheckedContinuation<Void, Error>)] = [:]
    var count: Int { waiters.count }
    func sleep(seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = (now + seconds, continuation)
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
    }
    func advance(_ seconds: TimeInterval) {
        now += seconds
        for (id, waiter) in waiters where waiter.0 <= now {
            waiters[id] = nil
            waiter.1.resume()
        }
    }
}

extension ChatGenerationCoordinatorTests {
    @Test("后台预算到期收尾；前台恢复使旧计时失效")
    func backgroundBudgetWithManualClock() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let clock = ManualGenerationClock()
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: { provider },
            configProvider: { ("test", nil) }, clock: clock, background: TestBackgroundExecution())
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        coordinator.enterBackground()
        for _ in 0..<1000 { if await clock.count >= 2 { break }; await Task.yield() }
        coordinator.enterForeground()
        await clock.advance(20)
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.isGenerating(id), "已经回前台，旧后台计时不能取消当前任务")
        coordinator.enterBackground()
        for _ in 0..<1000 { if await clock.count >= 2 { break }; await Task.yield() }
        await clock.advance(20)
        try await waitUntil { !coordinator.isGenerating(id) }
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.endReason == "backgroundExpired")
    }
}

extension ChatGenerationCoordinatorTests {
    @Test("停止后立即重试或发送，终态保存失败不得覆盖内存正文", arguments: [false, true])
    func failedTerminalSaveBlocksNextTurn(regenerate: Bool) async throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        let repository = GRDBChatRepository(queue: queue)
        let id = try conversation(repository)
        var providers: [ControlledGenerationProvider] = []
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            let provider = ControlledGenerationProvider(); providers.append(provider); return provider
        }, configProvider: { ("test", nil) })
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        providers[0].continuation.yield(.textDelta("未落盘正文"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.content == "未落盘正文" }
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_terminal BEFORE UPDATE ON message BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
        }
        coordinator.stop(conversationID: id)
        let messageID = try #require(coordinator.snapshot(conversationID: id).messages.last?.id)
        let accepted = regenerate
            ? await coordinator.regenerate(conversationID: id, messageID: messageID)
            : await coordinator.send(conversationID: id, text: "next")
        #expect(!accepted)
        #expect(try coordinator.snapshot(conversationID: id).hasUnsavedContent)
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.content == "未落盘正文")
        #expect(try repository.messages(in: id).count == 2)
        #expect(providers.dropFirst().allSatisfy { $0.request == nil })
    }

    @Test("发送事务等待时编辑的新草稿不能被成功回调清空")
    func draftEditedDuringPreparation() async throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        let repository = GRDBChatRepository(queue: queue)
        let id = try conversation(repository)
        let coordinator = ChatGenerationCoordinator(repository: repository,
            providerFactory: { ControlledGenerationProvider() }, configProvider: { ("test", nil) })
        let release = DispatchSemaphore(value: 0)
        // 占用写队列让 beginTurn 保持等待，模拟缓慢磁盘。
        await withCheckedContinuation { ready in
            DispatchQueue.global().async {
                queue.writeWithoutTransaction { _ in
                    ready.resume(); release.wait()
                }
            }
        }
        coordinator.setDraft("first", for: id)
        let sending = Task { await coordinator.send(conversationID: id, text: "first") }
        try await waitUntil { coordinator.isGenerating(id) }
        coordinator.setDraft("下一问", for: id)
        release.signal()
        #expect(await sending.value)
        #expect(coordinator.draft(for: id) == "下一问")
        coordinator.stop(conversationID: id)
    }

    @Test("准备期间删除失败后不留下无人管理的生成占位", arguments: [0, 1, 2])
    func deleteFailureDuringPreparation(previousTurn: Int) async throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        let repository = GRDBChatRepository(queue: queue)
        let id = try conversation(repository)
        try await queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_delete BEFORE DELETE ON conversation BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
        }
        var providers: [ControlledGenerationProvider] = []
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: {
            let provider = ControlledGenerationProvider(); providers.append(provider); return provider
        }, configProvider: { ("test", nil) })
        if previousTurn > 0 {
            #expect(await coordinator.send(conversationID: id, text: "previous"))
            providers[0].continuation.yield(.textDelta("previous reply"))
            providers[0].continuation.yield(.done(finishReason: "stop"))
            providers[0].continuation.finish()
            try await waitUntil { try repository.messages(in: id).last?.status == .completed }
        }
        let retryID = try repository.messages(in: id).last?.id
        let release = DispatchSemaphore(value: 0)
        await withCheckedContinuation { ready in
            DispatchQueue.global().async {
                queue.writeWithoutTransaction { _ in
                    ready.resume(); release.wait()
                }
            }
        }
        let sending = Task {
            if previousTurn == 2, let retryID {
                return await coordinator.regenerate(conversationID: id, messageID: retryID)
            }
            return await coordinator.send(conversationID: id, text: "hi")
        }
        try await waitUntil { coordinator.isGenerating(id) }
        let deletion = Task { try await coordinator.deleteConversation(id) }
        try await waitUntil { !coordinator.isGenerating(id) }
        release.signal()
        #expect(await sending.value == false)
        do { try await deletion.value; Issue.record("删除应失败") } catch { }
        try await waitUntil { try repository.messages(in: id).last?.status == .interrupted }
        #expect(!coordinator.isGenerating(id))
        #expect(providers.last?.request == nil)
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.generationID == repository.messages(in: id).last?.generationID)
    }

    @Test("模型结束原因不能覆盖主动停止原因")
    func stopReasonWinsOverModelReason() async throws {
        let repository = try makeRepository()
        let id = try conversation(repository)
        let provider = ControlledGenerationProvider()
        let coordinator = ChatGenerationCoordinator(repository: repository, providerFactory: { provider }, configProvider: { ("test", nil) })
        #expect(await coordinator.send(conversationID: id, text: "hi"))
        provider.continuation.yield(.finishReason("length"))
        provider.continuation.yield(.textDelta("partial"))
        try await waitUntil { try coordinator.snapshot(conversationID: id).messages.last?.content == "partial" }
        coordinator.stop(conversationID: id)
        #expect(try coordinator.snapshot(conversationID: id).messages.last?.endReason == "userStopped")
    }
}
