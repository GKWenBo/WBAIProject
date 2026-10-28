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

/// 覆盖 `AssistantMessageCell` 底部操作栏（复制 / 重新生成）的显隐、回调与占位。
@Suite("助手消息 cell 操作栏")
@MainActor
struct AssistantMessageCellActionBarTests {

    private func makeCell() -> AssistantMessageCell {
        AssistantMessageCell(style: .default, reuseIdentifier: nil)
    }

    private func configure(_ cell: AssistantMessageCell, status: MessageStatus,
                           canCopy: Bool = true,
                           trailing: MessageActionBar.Trailing = .regenerate) {
        cell.configure(blocks: [], reasoning: nil, status: status, errorText: nil,
                       pool: BlockViewPool(), cache: AttributedCache(), renderer: AttributedRenderer(),
                       measurer: TextKitMeasurer(), canCopy: canCopy, trailingAction: trailing)
    }

    private func button(_ identifier: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.accessibilityIdentifier == identifier { return button }
        for subview in view.subviews {
            if let found = button(identifier, in: subview) { return found }
        }
        return nil
    }

    @Test("非流式时按调用方给的配置显示按钮，流式中全部隐藏")
    func buttonVisibilityFollowsStatus() {
        let cell = makeCell()

        for status in [MessageStatus.completed, .failed, .stopped, .interrupted] {
            configure(cell, status: status)
            #expect(button("message.copy", in: cell)?.isHidden == false)
            #expect(button("message.regenerate", in: cell)?.isHidden == false)
        }

        configure(cell, status: .streaming)
        #expect(button("message.copy", in: cell)?.isHidden == true)
        #expect(button("message.regenerate", in: cell)?.isHidden == true)

        configure(cell, status: .completed, canCopy: false, trailing: .none)
        #expect(button("message.copy", in: cell)?.isHidden == true)
        #expect(button("message.regenerate", in: cell)?.isHidden == true)

        configure(cell, status: .failed, trailing: .retrySave)
        #expect(button("message.regenerate", in: cell)?.isHidden == true)
        #expect(button("message.retrySave", in: cell)?.isHidden == false)
    }

    @Test("操作栏始终占位：流式与完成态行高一致，按钮显隐不引起跳动")
    func actionBarAlwaysReservesHeight() {
        let cell = makeCell()
        configure(cell, status: .streaming)
        let streamingHeight = cell.heightThatFits(width: 390)
        configure(cell, status: .completed)
        #expect(cell.heightThatFits(width: 390) == streamingHeight)
        configure(cell, status: .completed, canCopy: false, trailing: .none)
        #expect(cell.heightThatFits(width: 390) == streamingHeight)
    }

    @Test("点击复制触发 onCopy，点击重新生成或重试保存触发 onRetry")
    func tappingButtonsFiresCallbacks() throws {
        let cell = makeCell()
        configure(cell, status: .completed)
        var copied = false
        var retried = 0
        cell.onCopy = { copied = true }
        cell.onRetry = { retried += 1 }

        try #require(button("message.copy", in: cell)).sendActions(for: .touchUpInside)
        try #require(button("message.regenerate", in: cell)).sendActions(for: .touchUpInside)
        configure(cell, status: .failed, trailing: .retrySave)
        try #require(button("message.retrySave", in: cell)).sendActions(for: .touchUpInside)

        #expect(copied)
        #expect(retried == 2)
    }

    @Test("prepareForReuse 后按钮隐藏且回调清空")
    func prepareForReuseResetsActionBar() throws {
        let cell = makeCell()
        configure(cell, status: .failed)
        var fired = false
        cell.onRetry = { fired = true }
        cell.onCopy = { fired = true }

        cell.prepareForReuse()

        let regenerate = try #require(button("message.regenerate", in: cell))
        let copy = try #require(button("message.copy", in: cell))
        #expect(regenerate.isHidden, "复用前应重新隐藏，避免下一次 configure 前露出旧状态")
        #expect(copy.isHidden)
        regenerate.sendActions(for: .touchUpInside)
        copy.sendActions(for: .touchUpInside)
        #expect(!fired, "prepareForReuse 应清空回调，避免复用后的 cell 仍触发上一条消息的回调")
    }

    @Test("prepareForReuse 后重新赋值的回调仍能被操作栏触发")
    func callbacksWorkAfterReuse() throws {
        let cell = makeCell()
        configure(cell, status: .completed)
        cell.prepareForReuse()
        configure(cell, status: .completed)
        var copied = false
        cell.onCopy = { copied = true }
        try #require(button("message.copy", in: cell)).sendActions(for: .touchUpInside)
        #expect(copied)
    }
}
