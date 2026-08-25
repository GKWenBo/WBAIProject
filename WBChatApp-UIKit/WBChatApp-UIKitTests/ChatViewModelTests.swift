import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 手动驱动的节流替身：测试里想合帧就调 fire()
final class ManualThrottle: StreamThrottling {
    var onTick: (() -> Void)?
    private(set) var isRunning = false
    func start() { isRunning = true }
    func stop() { isRunning = false }
    func fire() { onTick?() }
}

/// 按脚本吐 chunk 的 Provider 替身。
///
/// 偏离简报原文：原版在 `AsyncThrowingStream` 的构建闭包里同步 `for` 循环把全部 chunk
/// 一次性 yield 完再 finish。这个构建闭包在 `provider.stream(request)` 被调用的
/// 那一刻就会同步跑完，所有值在消费端的 `for try await` 开始迭代前就已经全部进了缓冲区；
/// 而缓冲区里已有值时 `next()` 不会产生真正的挂起，于是消费端的整条 for-await 循环
/// （包括流结束后 `finishStream` 里那次无条件的 `flush()`）会在 ViewModel 的
/// `Task { ... }` 被调度到的同一个执行回合里一次性跑完，早于测试里
/// `try await Task.sleep(...)` 之后的断言时机——导致「流式期间不出补丁」
/// 「流式期间不写库」「stop 后保留部分内容」等测试观测不到中间状态。
/// 用真实的微小延迟把逐个 chunk 的投递分散到不同的执行回合里，
/// 让测试的 sleep 窗口能够真正卡在流的中途；同时用 `onTermination` 把生产者
/// 和消费端的取消关联起来，避免消费端提前退出后生产者仍在后台空转。
final class ScriptedProvider: ChatProvider {
    private let chunks: [StreamChunk]
    private let error: Error?
    init(chunks: [StreamChunk], error: Error? = nil) {
        self.chunks = chunks
        self.error = error
    }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        let chunks = self.chunks
        let error = self.error
        return AsyncThrowingStream { continuation in
            let producer = Task {
                for chunk in chunks {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(25))
                    if Task.isCancelled { return }
                    continuation.yield(chunk)
                }
                if let error { continuation.finish(throwing: error) }
                else { continuation.finish() }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
}

@Suite("聊天 ViewModel")
@MainActor
struct ChatViewModelTests {

    private func makeViewModel(
        chunks: [StreamChunk],
        error: Error? = nil
    ) throws -> (ChatViewModel, ManualThrottle, GRDBChatRepository, String) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "deepseek-chat")
        let throttle = ManualThrottle()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: { ScriptedProvider(chunks: chunks, error: error) },
                                      systemPrompt: nil,
                                      model: "deepseek-chat",
                                      throttle: throttle)
        return (viewModel, throttle, repository, conversation.id)
    }

    /// 等流式任务跑完
    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("发送后立刻出现用户消息与助手占位")
    func sendInsertsTwoMessages() async throws {
        let (viewModel, _, _, _) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("你好")
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].role == .user)
        #expect(viewModel.state.messages[0].text == "你好")
        #expect(viewModel.state.messages[1].role == .assistant)
        await waitForStreamEnd(viewModel)
    }

    @Test("空白输入不发送")
    func blankInputIgnored() throws {
        let (viewModel, _, _, _) = try makeViewModel(chunks: [])
        viewModel.send("   \n ")
        #expect(viewModel.state.messages.isEmpty)
    }

    @Test("流式期间不出补丁，节流触发才出")
    func patchesOnlyOnThrottleTick() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("你"), .textDelta("好"), .done(finishReason: "stop")])

        var patches: [BlockPatch] = []
        viewModel.onOutput = { output in
            if case .blocksPatched(_, let patch) = output { patches.append(patch) }
        }

        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        #expect(patches.isEmpty, "还没到帧回调就不该出补丁")

        throttle.fire()
        #expect(!patches.isEmpty)
        await waitForStreamEnd(viewModel)
    }

    @Test("多个 delta 被合并成一次补丁")
    func deltasAreCoalesced() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: (0..<10).map { .textDelta("字\($0)") } + [.done(finishReason: "stop")])

        var patchCount = 0
        viewModel.onOutput = { output in
            if case .blocksPatched = output { patchCount += 1 }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        #expect(patchCount == 1, "一帧内的多个 delta 应合并为一次补丁")
        await waitForStreamEnd(viewModel)
    }

    @Test("节流器随流式启停")
    func throttleLifecycle() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("hi")
        #expect(throttle.isRunning)
        await waitForStreamEnd(viewModel)
        #expect(!throttle.isRunning)
    }

    @Test("思考增量走独立通路")
    func reasoningGoesToSeparateOutput() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.reasoningDelta("想一想"), .done(finishReason: "stop")])

        var reasoning: String?
        viewModel.onOutput = { output in
            if case .reasoningUpdated(_, let text) = output { reasoning = text }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        #expect(reasoning == "想一想")
        await waitForStreamEnd(viewModel)
    }

    @Test("流结束后全文与用量落库")
    func persistsOnFinish() async throws {
        let (viewModel, throttle, repository, conversationID) = try makeViewModel(
            chunks: [.textDelta("完整回复"),
                     .usage(TokenUsage(prompt: 3, completion: 9)),
                     .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(try repository.messages(in: conversationID)
            .first { $0.role == .assistant })
        #expect(assistant.content == "完整回复")
        #expect(assistant.status == .completed)
        #expect(assistant.completionTokens == 9)
    }

    @Test("流式期间不写库")
    func noWriteDuringStreaming() async throws {
        let (viewModel, throttle, repository, conversationID) = try makeViewModel(
            chunks: [.textDelta("片段"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(30))
        throttle.fire()

        let assistant = try repository.messages(in: conversationID).first { $0.role == .assistant }
        // 占位是 streaming 状态且内容为空，说明中途没有把片段写进去
        #expect(assistant?.content.isEmpty == true || assistant?.status == .streaming)
        await waitForStreamEnd(viewModel)
    }

    @Test("失败时保留已生成内容并给出错误")
    func failureKeepsPartialContent() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("已经写了一半")],
            error: ChatError.serverError(status: 500, message: "炸了"))

        var failure: ChatError?
        viewModel.onOutput = { output in
            if case .failed(let error, _) = output { failure = error }
        }
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        #expect(failure == .serverError(status: 500, message: "炸了"))
        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.text == "已经写了一半")
        #expect(assistant.status == .failed)
    }

    @Test("stop 把消息标记为已停止并保留内容")
    func stopMarksStopped() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("写到一半")] + (0..<1000).map { _ in .textDelta("续") })
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(30))
        throttle.fire()
        viewModel.stop()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.status == .stopped)
        #expect(!assistant.text.isEmpty)
    }

    @Test("流式期间 canSend 为假")
    func canSendIsFalseWhileStreaming() async throws {
        let (viewModel, _, _, _) = try makeViewModel(
            chunks: (0..<500).map { _ in .textDelta("续") })
        viewModel.send("hi")
        #expect(viewModel.state.isStreaming)
        #expect(!viewModel.state.canSend)
        viewModel.stop()
        await waitForStreamEnd(viewModel)
    }

    @Test("loadHistory 读回已存消息")
    func loadHistory() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("历史回复"), .done(finishReason: "stop")])
        viewModel.send("历史提问")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        viewModel.loadHistory()
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].text == "历史提问")
    }

    @Test("blocks(for:) 返回该消息切好的块")
    func blocksForMessage() async throws {
        let (viewModel, throttle, _, _) = try makeViewModel(
            chunks: [.textDelta("# 标题\n\n正文\n"), .done(finishReason: "stop")])
        viewModel.send("hi")
        try await Task.sleep(for: .milliseconds(50))
        throttle.fire()
        await waitForStreamEnd(viewModel)

        let assistantID = try #require(viewModel.state.messages.last?.id)
        let blocks = viewModel.blocks(for: assistantID)
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
    }
}
