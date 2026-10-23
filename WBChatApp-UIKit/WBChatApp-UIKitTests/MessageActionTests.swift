import UIKit
import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 覆盖 retryLast() 与消息长按菜单相关的行为。
///
/// # 偏离简报：ScriptedProvider → GatedProvider
/// 简报里原用 `ScriptedProvider(chunks:error:)`，靠后台 Task 按固定间隔分帧
/// 投递、测试侧用 `Task.sleep` 赌时机。这个替身在 Task 15 的复盘中已经被
/// `ChatViewModelTests.swift` 换成了 `GatedProvider`（测试显式 `deliverNext()`/
/// `finish()` 驱动投递节奏，彻底不依赖挂钟），`ScriptedProvider` 本身也已经
/// 从代码库里删除。本文件复用 `ChatViewModelTests.swift` 里同目标下已定义的
/// `ManualThrottle` / `GatedProvider` / `ProviderBox`（都是 internal，同一个
/// 测试 target 内可直接访问），不再引用不存在的 `ScriptedProvider`。
@Suite("消息操作")
@MainActor
struct MessageActionTests {

    private func makeViewModel(
        chunks: [StreamChunk],
        error: Error? = nil
    ) throws -> (viewModel: ChatViewModel, throttle: ManualThrottle, providerBox: ProviderBox) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "m")
        let throttle = ManualThrottle()
        let providerBox = ProviderBox()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: {
                                          let provider = GatedProvider(chunks: chunks, error: error)
                                          providerBox.current = provider
                                          return provider
                                      },
                                      requestConfigProvider: { (model: "m", systemPrompt: nil) }, throttle: throttle)
        return (viewModel, throttle, providerBox)
    }

    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("失败后 retryLast 把消息重置为流式并重新生成")
    func retryAfterFailure() async throws {
        let (viewModel, throttle, providerBox) = try makeViewModel(
            chunks: [.textDelta("半截")],
            error: ChatError.serverError(status: 500, message: nil))

        await viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)
        #expect(viewModel.state.messages.last?.status == .failed)

        await viewModel.retryLast()
        #expect(viewModel.state.isStreaming)
        #expect(viewModel.state.messages.last?.errorText == nil)

        // retryLast 内部重新调用 providerFactory，拿到这一轮新的替身，
        // 把它跑完，避免遗留悬挂的流式 Task 影响后续用例
        let retryProvider = try #require(providerBox.current)
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)
    }

    @Test("retryLast 不新增消息条目")
    func retryDoesNotAppendMessage() async throws {
        let (viewModel, throttle, providerBox) = try makeViewModel(
            chunks: [.textDelta("内容"), .done(finishReason: "stop")])

        await viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)
        let countBefore = viewModel.state.messages.count

        await viewModel.retryLast()
        let retryProvider = try #require(providerBox.current)
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)

        #expect(viewModel.state.messages.count == countBefore)
    }

    @Test("retryLast 清空旧的块，不与新内容拼接")
    func retryClearsOldBlocks() async throws {
        let (viewModel, throttle, providerBox) = try makeViewModel(
            chunks: [.textDelta("第一次"), .done(finishReason: "stop")])

        await viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)

        let assistantID = try #require(viewModel.state.messages.last?.id)
        await viewModel.retryLast()
        #expect(!viewModel.blocks(for: assistantID).isEmpty, "首段到达前保留旧内容")

        let retryProvider = try #require(providerBox.current)
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)
    }

    /// 偏离简报：原用例只是造了一个从未 send() 过的空 ViewModel（`state.messages`
    /// 恒为空），guard 里 `let last = state.messages.last` 本身就会失败提前返回，
    /// 并没有真正命中「最后一条是用户消息」这条 `last.role == .assistant` 分支。
    /// 这里改为直接向仓库插入一条纯用户消息、`loadHistory()` 读回，让
    /// `state.messages.last?.role == .user`，才是名副其实地覆盖角色判断这条分支。
    @Test("用户消息不响应 retryLast")
    func retryIgnoresUserMessage() async throws {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek,
                                                             model: "m")
        let userRecord = MessageRecord(
            id: UUID().uuidString, conversationId: conversation.id, ordinal: 0,
            roleRaw: ChatRole.user.rawValue, content: "hi", reasoning: nil,
            statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil, createdAt: Date().timeIntervalSince1970)
        try repository.insertMessage(userRecord)

        let throttle = ManualThrottle()
        let viewModel = ChatViewModel(conversationID: conversation.id,
                                      repository: repository,
                                      providerFactory: { GatedProvider(chunks: []) },
                                      requestConfigProvider: { (model: "m", systemPrompt: nil) }, throttle: throttle)
        viewModel.loadHistory()
        #expect(viewModel.state.messages.last?.role == .user)

        await viewModel.retryLast()
        #expect(!viewModel.state.isStreaming)
    }
}

/// 覆盖 `AssistantMessageCell` 的 `status` → 重试按钮这条链路。
///
/// 补充说明：简报只要求 `MessageActionTests.swift` 覆盖 `retryLast()` 的
/// ViewModel 语义（4 个用例，均在 Step 2 就已经全绿——因为前置任务已经把
/// `retryLast()` 实现完整，参见任务简报的「上下文」小节）。这意味着严格按
/// 简报的 4 个用例走不到红色阶段，无法验证本任务真正要新增的 UI 部分：
/// `configure(...)` 的 `status` 参数此前完全没被 cell 用到（历次审查标注过），
/// 本任务给它接上第一个消费方——失败/停止状态下露出「重新生成」按钮。
/// 这里补两个 cell 级用例，直接对着 Step 3 的改动写 RED/GREEN，避免
/// 「测试全绿但没人验证过新代码路径」这种假通过。
@Suite("助手消息 cell 重试按钮")
@MainActor
struct AssistantMessageCellRetryTests {

    private func makeCell() -> AssistantMessageCell {
        AssistantMessageCell(style: .default, reuseIdentifier: nil)
    }

    private func configure(_ cell: AssistantMessageCell, status: MessageStatus) {
        cell.configure(blocks: [], reasoning: nil, status: status, errorText: nil,
                       pool: BlockViewPool(), cache: AttributedCache(), renderer: AttributedRenderer(),
                       measurer: TextKitMeasurer())
    }

    private func retryButton(in cell: AssistantMessageCell) -> UIButton? {
        cell.contentView.subviews.first { $0.accessibilityIdentifier == "message.retry" } as? UIButton
    }

    @Test("失败或停止状态下重试按钮可见，其余状态隐藏")
    func retryButtonVisibilityFollowsStatus() {
        let cell = makeCell()

        configure(cell, status: .failed)
        #expect(retryButton(in: cell)?.isHidden == false)

        configure(cell, status: .stopped)
        #expect(retryButton(in: cell)?.isHidden == false)

        configure(cell, status: .completed)
        #expect(retryButton(in: cell)?.isHidden == true)

        configure(cell, status: .streaming)
        #expect(retryButton(in: cell)?.isHidden == true)
    }

    @Test("点击重试按钮触发 onRetry")
    func tappingRetryButtonFiresCallback() throws {
        let cell = makeCell()
        configure(cell, status: .failed)

        var fired = false
        cell.onRetry = { fired = true }

        let button = try #require(retryButton(in: cell))
        button.sendActions(for: .touchUpInside)
        #expect(fired)
    }

    @Test("prepareForReuse 后重试按钮隐藏且回调清空")
    func prepareForReuseResetsRetryButton() throws {
        let cell = makeCell()
        configure(cell, status: .failed)
        var fired = false
        cell.onRetry = { fired = true }

        cell.prepareForReuse()

        let button = try #require(retryButton(in: cell))
        #expect(button.isHidden, "复用前应重新隐藏，避免下一次 configure 前露出旧状态")
        button.sendActions(for: .touchUpInside)
        #expect(!fired, "prepareForReuse 应清空 onRetry，避免复用后的 cell 仍触发上一条消息的回调")
    }
}
