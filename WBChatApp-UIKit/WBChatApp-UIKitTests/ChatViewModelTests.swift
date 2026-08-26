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

/// 由测试显式驱动投递节奏的 Provider 替身，彻底不依赖挂钟。
///
/// # 为什么要换掉 ScriptedProvider
/// 旧版用「后台 Task + 每 chunk 前 sleep(25ms)」分帧投递，测试用
/// `Task.sleep(30~50ms)` 赌它跑到中途再操作。这是挂钟耦合：CI 机器一卡，
/// 25ms 的产出节奏和测试的等待窗口就可能错位，`stopMarksStopped` 因此
/// 实测 5 次有 1 次失败。
///
/// # 握手机制
/// `stream(_:)` 用 `AsyncThrowingStream(unfolding:)` 构建流——它的
/// `produce` 闭包在消费端每次调用 `next()`（也就是 `for try await` 循环
/// 每次要下一个值）时被直接调用，运行在消费端所在的执行上下文里。
/// 于是"这个闭包又被调用了一次"本身就是一个精确、免锁的信号：
/// 证明上一个值已经被 `for` 循环体（`handle(chunk)` + `checkCancellation()`）
/// 完整跑完，循环体里没有任何其它挂起点，所以这个信号绝不会早到或迟到。
///
/// 具体到收发两端：
/// - `outbox` 是"待消费的值"邮箱，`demandRound` 是"消费端已经进入过几次
///   `next()`"的计数器。`produce()` 邮箱为空时反复 `await Task.yield()`
///   （不是 sleep，只是把执行权让给调度器），一旦邮箱有值或流被要求结束就
///   取走并让计数器 +1。
/// - `deliverNext()` 把值放进邮箱后，同样反复 `Task.yield()` 直到看见
///   `demandRound` 真的往前走了一格，这才证明消费端已经把值收下并处理完，
///   此时才返回——测试拿到返回值后看到的状态就是这个 chunk 处理完之后的
///   状态，不需要再猜"是不是已经跑完了"。
/// - `Task.isCancelled` 的检查放在 `produce()` 的等待循环里，靠消费端
///   自己的取消状态驱动，不依赖任何额外的取消回调：`stop()` 取消
///   `streamTask` 后，卡在 `Task.yield()` 里的 `produce()` 会在下一轮检查
///   时发现被取消并抛出，`for try await` 随之退出，不会永久挂起。
final class GatedProvider: ChatProvider, @unchecked Sendable {
    private let chunks: [StreamChunk]
    private let error: Error?
    private var index = 0

    /// 待消费端取走的值；nil 表示当前邮箱是空的
    private var outbox: StreamChunk?
    /// 测试已要求结束流（正常结束或带错误结束）
    private var outboxIsFinish = false
    /// 消费端调用 `next()`（即进入 `produce()`）的累计次数，一进函数体、
    /// 还没开始等邮箱之前就 +1——它代表"消费端已经发起了第几次要货"。
    /// 注意不能在拿到邮箱值、正要返回之前才 +1：那样这次自增本身就是在
    /// 应答"当前正在交付的这个 chunk"，deliverNext() 会把它误判成
    /// "上一个 chunk 已处理完"的信号，从而在消费端真正跑完
    /// `handle(chunk)` 之前就提前返回——这正是 reasoningGoesToSeparateOutput
    /// 一度间歇性失败的根因。
    private var requested = 0

    init(chunks: [StreamChunk], error: Error? = nil) {
        self.chunks = chunks
        self.error = error
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream<StreamChunk, Error> { [weak self] in
            try await self?.produce()
        }
    }

    /// 消费端 `next()` 的真正实现：邮箱空且未要求结束时，反复让出执行权
    /// 等测试投递；不用挂钟，纯靠调度器把控制权交还给正在驱动的测试代码。
    private func produce() async throws -> StreamChunk? {
        requested += 1
        while outbox == nil && !outboxIsFinish {
            if Task.isCancelled { throw CancellationError() }
            await Task.yield()
        }
        if let chunk = outbox {
            outbox = nil
            return chunk
        }
        outboxIsFinish = false
        if let error { throw error }
        return nil
    }

    /// 投递下一个 chunk，并等到消费端真正处理完它才返回。
    /// `index`（自增后）就是"已经投递过的 chunk 数量"；只要 `requested`
    /// 还没超过它，说明消费端要么还没来取这个值，要么刚拿到手、正在跑
    /// 循环体（还没来得及为下一个值再调一次 `next()`）——都不能算"处理完"。
    /// `requested > index` 才证明消费端已经为"再下一个值"发起了新的
    /// `next()` 调用，而这只会发生在上一轮 `handle(chunk)` +
    /// `checkCancellation()` 完整跑完之后。调用方在这行代码之后能安全
    /// 断言"这个 chunk 已生效"。
    func deliverNext() async {
        guard index < chunks.count else { return }
        let chunk = chunks[index]
        index += 1
        outbox = chunk
        while requested <= index {
            await Task.yield()
        }
    }

    /// 投递剩余全部 chunk，再结束流（正常结束，或带初始化时传入的错误结束）
    func finish() async {
        while index < chunks.count {
            await deliverNext()
        }
        outboxIsFinish = true
    }
}

/// 装最近一次由 providerFactory 创建出的 GatedProvider。
/// send()/retryLast() 每次起新的一轮流都会调用 providerFactory 造一个
/// 新实例（跟生产代码语义一致），测试靠这个盒子拿到"当前这一轮"的替身。
final class ProviderBox {
    var current: GatedProvider?
}

@Suite("聊天 ViewModel")
@MainActor
struct ChatViewModelTests {

    private func makeViewModel(
        chunks: [StreamChunk],
        error: Error? = nil
    ) throws -> (viewModel: ChatViewModel, throttle: ManualThrottle,
                 repository: GRDBChatRepository, conversationID: String,
                 providerBox: ProviderBox) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "deepseek-chat")
        let throttle = ManualThrottle()
        let providerBox = ProviderBox()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: {
                                          let provider = GatedProvider(chunks: chunks, error: error)
                                          providerBox.current = provider
                                          return provider
                                      },
                                      systemPrompt: nil,
                                      model: "deepseek-chat",
                                      throttle: throttle)
        return (viewModel, throttle, repository, conversation.id, providerBox)
    }

    /// 等流式任务跑完。这是对"流真正结束"的轮询，不是等固定时长——
    /// 只要 GatedProvider 被正确 deliverNext()/finish()/取消，就会很快退出
    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("发送后立刻出现用户消息与助手占位")
    func sendInsertsTwoMessages() async throws {
        let (viewModel, _, _, _, providerBox) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("你好")
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].role == .user)
        #expect(viewModel.state.messages[0].text == "你好")
        #expect(viewModel.state.messages[1].role == .assistant)

        let provider = try #require(providerBox.current)
        await provider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("空白输入不发送")
    func blankInputIgnored() throws {
        let (viewModel, _, _, _, _) = try makeViewModel(chunks: [])
        viewModel.send("   \n ")
        #expect(viewModel.state.messages.isEmpty)
    }

    @Test("流式期间不出补丁，节流触发才出")
    func patchesOnlyOnThrottleTick() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("你"), .textDelta("好"), .done(finishReason: "stop")])

        var patches: [BlockPatch] = []
        viewModel.onOutput = { output in
            if case .blocksPatched(_, let patch) = output { patches.append(patch) }
        }

        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        // 两个文本增量都已经被消费端确认收下，但还没到节流帧回调
        await provider.deliverNext()
        await provider.deliverNext()
        #expect(patches.isEmpty, "还没到帧回调就不该出补丁")

        throttle.fire()
        #expect(!patches.isEmpty)

        await provider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("多个 delta 被合并成一次补丁")
    func deltasAreCoalesced() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: (0..<10).map { .textDelta("字\($0)") } + [.done(finishReason: "stop")])

        var patchCount = 0
        viewModel.onOutput = { output in
            if case .blocksPatched = output { patchCount += 1 }
        }
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        for _ in 0..<10 { await provider.deliverNext() }
        throttle.fire()
        #expect(patchCount == 1, "一帧内的多个 delta 应合并为一次补丁")

        await provider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("节流器随流式启停")
    func throttleLifecycle() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(chunks: [.done(finishReason: "stop")])
        viewModel.send("hi")
        #expect(throttle.isRunning)

        let provider = try #require(providerBox.current)
        await provider.finish()
        await waitForStreamEnd(viewModel)
        #expect(!throttle.isRunning)
    }

    @Test("ViewModel 释放时会停止节流器，避免 CADisplayLink 自持有循环导致泄漏")
    func deinitStopsThrottle() async throws {
        // 故意不走 makeViewModel() 那个共享 helper：它返回的元组里 viewModel 字段
        // 如果先被 let 绑成另一个名字（哪怕后面把 optional var 设成 nil），
        // 元组本身在 -Onone 调试构建下会一直存活到作用域结束，仍然强引用着
        // ChatViewModel，deinit 根本不会触发——这曾让这条用例本身误报失败。
        // 这里让「初始化表达式的结果」只被赋给唯一一个 optional var，
        // 才能保证置 nil 就是这个对象唯一强引用的释放点。
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                              model: "deepseek-chat")
        let throttle = ManualThrottle()
        let providerBox = ProviderBox()

        var viewModel: ChatViewModel? = ChatViewModel(
            conversationID: conversation.id,
            repository: repository,
            providerFactory: {
                let provider = GatedProvider(chunks: [.done(finishReason: "stop")], error: nil)
                providerBox.current = provider
                return provider
            },
            systemPrompt: nil,
            model: "deepseek-chat",
            throttle: throttle)

        viewModel?.send("hi")
        #expect(throttle.isRunning)

        // 流还没结束就释放 ViewModel（对应场景：抽屉切会话时旧 ViewModel 该被回收，
        // 但流式还没跑完）。deinit 里如果漏了 throttle.stop()，CADisplayLink 会靠
        // 强引用 target 自环，永远不被系统回收；这里用 ManualThrottle.isRunning
        // 断言 stop() 确实被调用到了。
        let provider = try #require(providerBox.current)
        viewModel = nil
        withExtendedLifetime(provider) {}
        #expect(!throttle.isRunning)
    }

    @Test("思考增量走独立通路")
    func reasoningGoesToSeparateOutput() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.reasoningDelta("想一想"), .done(finishReason: "stop")])

        var reasoning: String?
        viewModel.onOutput = { output in
            if case .reasoningUpdated(_, let text) = output { reasoning = text }
        }
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        #expect(reasoning == "想一想")

        await provider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("流结束后全文与用量落库")
    func persistsOnFinish() async throws {
        let (viewModel, throttle, repository, conversationID, providerBox) = try makeViewModel(
            chunks: [.textDelta("完整回复"),
                     .usage(TokenUsage(prompt: 3, completion: 9)),
                     .done(finishReason: "stop")])
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        await provider.finish()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(try repository.messages(in: conversationID)
            .first { $0.role == .assistant })
        #expect(assistant.content == "完整回复")
        #expect(assistant.status == .completed)
        #expect(assistant.completionTokens == 9)
    }

    @Test("流式期间不写库")
    func noWriteDuringStreaming() async throws {
        let (viewModel, throttle, repository, conversationID, providerBox) = try makeViewModel(
            chunks: [.textDelta("片段"), .done(finishReason: "stop")])
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()

        let assistant = try repository.messages(in: conversationID).first { $0.role == .assistant }
        // 拆成两条独立断言：用 || 连接会让这条测试恒真（当前实现下两个条件天然同时
        // 成立），将来若引入"中途只写 content 不改 status"这类回归，原写法发现不了
        #expect(assistant?.content.isEmpty == true, "中途不该把片段写进去")
        #expect(assistant?.status == .streaming, "中途状态应仍是 streaming")

        await provider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("失败时保留已生成内容并给出错误")
    func failureKeepsPartialContent() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("已经写了一半")],
            error: ChatError.serverError(status: 500, message: "炸了"))

        var failure: ChatError?
        viewModel.onOutput = { output in
            if case .failed(let error, _) = output { failure = error }
        }
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        await provider.finish()
        await waitForStreamEnd(viewModel)

        #expect(failure == .serverError(status: 500, message: "炸了"))
        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.text == "已经写了一半")
        #expect(assistant.status == .failed)
    }

    @Test("stop 把消息标记为已停止并保留内容")
    func stopMarksStopped() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("写到一半")])
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        viewModel.stop()
        await waitForStreamEnd(viewModel)

        let assistant = try #require(viewModel.state.messages.last)
        #expect(assistant.status == .stopped)
        #expect(!assistant.text.isEmpty)
    }

    @Test("流式期间 canSend 为假")
    func canSendIsFalseWhileStreaming() async throws {
        let (viewModel, _, _, _, _) = try makeViewModel(chunks: [])
        viewModel.send("hi")
        #expect(viewModel.state.isStreaming)
        #expect(!viewModel.state.canSend)
        viewModel.stop()
        await waitForStreamEnd(viewModel)
    }

    @Test("loadHistory 读回已存消息")
    func loadHistory() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("历史回复"), .done(finishReason: "stop")])
        viewModel.send("历史提问")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        await provider.finish()
        await waitForStreamEnd(viewModel)

        viewModel.loadHistory()
        #expect(viewModel.state.messages.count == 2)
        #expect(viewModel.state.messages[0].text == "历史提问")
    }

    @Test("blocks(for:) 返回该消息切好的块")
    func blocksForMessage() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("# 标题\n\n正文\n"), .done(finishReason: "stop")])
        viewModel.send("hi")
        let provider = try #require(providerBox.current)

        await provider.deliverNext()
        throttle.fire()
        await provider.finish()
        await waitForStreamEnd(viewModel)

        let assistantID = try #require(viewModel.state.messages.last?.id)
        let blocks = viewModel.blocks(for: assistantID)
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
    }

    /// 流式期间调用 retryLast 应该是无操作：否则旧流仍在后台跑，
    /// 会把内容写进被新一轮重置的缓冲区，污染新流；且 stop() 会失去旧任务的引用
    @Test("流式进行中调用 retryLast 不产生副作用")
    func retryLastNoOpWhileStreaming() async throws {
        let (viewModel, _, _, _, _) = try makeViewModel(chunks: [.textDelta("续")])
        viewModel.send("hi")
        #expect(viewModel.state.isStreaming)

        let messagesBefore = viewModel.state.messages
        viewModel.retryLast()
        #expect(viewModel.state.messages == messagesBefore, "流式中的 retryLast 不该改变消息列表")
        #expect(viewModel.state.isStreaming)

        viewModel.stop()
        await waitForStreamEnd(viewModel)
    }

    /// retryLast 必须先发出 blocksReset 通知下游整体清空块视图，
    /// 再让新一轮流开始产出 blocksPatched，顺序颠倒会导致新内容追加在旧内容后面
    @Test("retryLast 发出 blocksReset 且排在 blocksPatched 之前")
    func retryEmitsBlocksResetBeforePatches() async throws {
        let (viewModel, throttle, _, _, providerBox) = try makeViewModel(
            chunks: [.textDelta("一些内容"), .done(finishReason: "stop")])

        viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)

        enum Event: Equatable { case reset, patched }
        var events: [Event] = []
        viewModel.onOutput = { output in
            switch output {
            case .blocksReset: events.append(.reset)
            case .blocksPatched: events.append(.patched)
            default: break
            }
        }

        viewModel.retryLast()
        // retryLast 内部会重新调用 providerFactory，拿到这一轮新的替身
        let retryProvider = try #require(providerBox.current)
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)

        #expect(events.first == .reset, "blocksReset 应该是 retryLast 之后的第一个相关事件")
        let resetIndex = try #require(events.firstIndex(of: .reset))
        let patchIndices = events.indices.filter { events[$0] == .patched }
        #expect(!patchIndices.isEmpty, "retry 后的新一轮流应该产出 blocksPatched")
        #expect(patchIndices.allSatisfy { $0 > resetIndex }, "所有 blocksPatched 都应排在 blocksReset 之后")
    }

    /// send() 一次调用会插入两条消息并进入流式态，这些字段赋值应合并成一次
    /// state 提交，避免下游对同一个逻辑动作应用多次快照/动画
    @Test("send 一次调用只触发一次 stateChanged")
    func sendFiresStateChangedOnce() async throws {
        let (viewModel, _, _, _, providerBox) = try makeViewModel(chunks: [.done(finishReason: "stop")])

        var stateChangeCount = 0
        viewModel.onOutput = { output in
            if case .stateChanged = output { stateChangeCount += 1 }
        }

        viewModel.send("hi")
        #expect(stateChangeCount == 1)

        let provider = try #require(providerBox.current)
        await provider.finish()
        await waitForStreamEnd(viewModel)
    }
}
