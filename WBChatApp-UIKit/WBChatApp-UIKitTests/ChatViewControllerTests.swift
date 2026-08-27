import UIKit
import Foundation
import Testing
@testable import WBChatApp_UIKit

/// Task 20 审查三条修复的 ChatViewController 级接线测试。
///
/// 项目里此前没有任何 ChatViewController 级别的单测——Critical 1、Critical 2
/// 都出在「ViewModel 语义本身没问题，但 VC 把回调接错了 / 没有及时刷新已存在
/// 的 cell」这一层，只测 ChatViewModel 或只测 AssistantMessageCell 都盯不住
/// 这层接线，所以在这里补上。
@Suite("聊天 VC")
@MainActor
struct ChatViewControllerTests {

    // MARK: - 装配

    private func make(
        chunks: [StreamChunk],
        error: Error? = nil
    ) throws -> (vc: ChatViewController, viewModel: ChatViewModel, throttle: ManualThrottle,
                 repository: GRDBChatRepository, conversationID: String, providerBox: ProviderBox) {
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
                                      requestConfigProvider: { (model: "deepseek-chat", systemPrompt: nil) },
                                      throttle: throttle)
        let vc = ChatViewController(viewModel: viewModel,
                                    renderer: AttributedRenderer(),
                                    cache: AttributedCache(),
                                    pool: BlockViewPool())
        return (vc, viewModel, throttle, repository, conversation.id, providerBox)
    }

    private func waitForStreamEnd(_ viewModel: ChatViewModel) async {
        for _ in 0..<200 {
            if !viewModel.state.isStreaming { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// `UITableViewDiffableDataSource.apply(_:animatingDifferences:)` 文档明确说是异步的，
    /// 即便 `animatingDifferences: false` 也不保证调用返回时快照已经生效。
    /// 这里不赌挂钟，纯靠协作式让出等它跑完——和仓库里 GatedProvider/语音状态机
    /// 测试用的是同一套手法。
    private func waitUntil(_ condition: @autoclosure @escaping () -> Bool,
                           timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            await Task.yield()
        }
    }

    /// 只有把 vc 真正挂进一个 UIWindow 并跑一次布局，`tableView.cellForRow(at:)`
    /// 才会返回非 nil——它只认「当前可见」的 cell，这是 UIKit 自己的内部簿记，
    /// 不受 dataSource 快照是否已应用影响。调用方必须持有返回的 window 到测试结束，
    /// 否则它会被提前释放，vc 也跟着被移出视图层级。
    private func attachToWindow(_ vc: UIViewController) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.layoutIfNeeded()
        return window
    }

    /// `ChatViewController` 的 `tableView` 属性是 private（且与 `UITableViewDelegate` 的
    /// `tableView(_:cellForRowAt:)` 等方法同名，`@testable import` 也拿不到），
    /// 所以从 `vc.view` 的直接子视图里按 accessibilityIdentifier 找回真实实例。
    private func tableView(of vc: ChatViewController) throws -> UITableView {
        try #require(vc.view.subviews.first {
            ($0 as? UITableView)?.accessibilityIdentifier == "chat.tableView"
        } as? UITableView)
    }

    private func diffableDataSource(_ vc: ChatViewController) throws -> UITableViewDiffableDataSource<Int, String> {
        try #require(try tableView(of: vc).dataSource as? UITableViewDiffableDataSource<Int, String>)
    }

    /// 与 MessageActionTests 里的同名 helper 逻辑一致：靠 accessibilityIdentifier
    /// 从 cell 的 contentView 里找「重新生成」按钮，不新增测试专用的公开 API。
    private func retryButton(in cell: AssistantMessageCell) -> UIButton? {
        cell.contentView.subviews.first { $0.accessibilityIdentifier == "message.retry" } as? UIButton
    }

    private func insert(_ repository: GRDBChatRepository, id: String, conversationID: String,
                        ordinal: Int, role: ChatRole, content: String,
                        status: MessageStatus, errorText: String? = nil) throws {
        try repository.insertMessage(MessageRecord(
            id: id, conversationId: conversationID, ordinal: ordinal,
            roleRaw: role.rawValue, content: content, reasoning: nil,
            statusRaw: status.rawValue, errorMessage: errorText,
            promptTokens: nil, completionTokens: nil,
            createdAt: Date().timeIntervalSince1970))
    }

    // MARK: - Critical 1：重试按钮不能误重试成别的消息

    /// 复现简报里的场景：助手回复 A 失败，用户又发了一条 B 并且 B 已经流完。
    /// A 的「重新生成」按钮理应还留在屏幕上（因为 A 自己确实是失败状态），
    /// 但点它绝不能把 B 重跑一遍——B 才是 `state.messages.last`。
    @Test("点击非最后一条消息上的重试按钮，不会误重试成当前最后一条消息")
    func staleRetryButtonDoesNotRetryWrongMessage() throws {
        let (vc, viewModel, _, repository, conversationID, providerBox) = try make(chunks: [])

        try insert(repository, id: "userA", conversationID: conversationID, ordinal: 0,
                  role: .user, content: "问题A", status: .completed)
        try insert(repository, id: "assistantA", conversationID: conversationID, ordinal: 1,
                  role: .assistant, content: "失败的回复", status: .failed, errorText: "出错了")
        try insert(repository, id: "userB", conversationID: conversationID, ordinal: 2,
                  role: .user, content: "问题B", status: .completed)
        try insert(repository, id: "assistantB", conversationID: conversationID, ordinal: 3,
                  role: .assistant, content: "完整回复", status: .completed)

        _ = vc.view // 触发 viewDidLoad -> loadHistory -> applySnapshot

        let table = try tableView(of: vc)
        let ds = try diffableDataSource(vc)
        let indexPathA = try #require(ds.indexPath(for: "assistantA"))
        let cellA = try #require(
            ds.tableView(table, cellForRowAt: indexPathA) as? AssistantMessageCell)

        // 前置条件：A 自己状态是 failed，按钮理应可见——这不是 bug
        #expect(retryButton(in: cellA)?.isHidden == false)

        retryButton(in: cellA)?.sendActions(for: .touchUpInside)

        // 关键断言：点 A 的按钮不该起新的一轮流，B 的状态、消息列表都不该变
        #expect(providerBox.current == nil, "点击 A 残留的按钮不该调用 providerFactory 起新的一轮流")
        #expect(!viewModel.state.isStreaming)
        #expect(viewModel.state.messages.last?.id == "assistantB")
        #expect(viewModel.state.messages.last?.status == .completed)
        #expect(viewModel.state.messages.first { $0.id == "assistantA" }?.status == .failed,
                "A 自己的状态也不该被这次误触发改动")
    }

    /// 正向对照：真的点在「最后一条」失败的助手消息上时，必须正常触发 retryLast，
    /// 确认 Critical 1 的 guard 没有矫枉过正把合法点击也挡掉。
    @Test("点击最后一条失败的助手消息的重试按钮，正常触发 retryLast")
    func retryButtonOnActualLastMessageTriggersRetry() async throws {
        let (vc, viewModel, throttle, providerBox) = try {
            let r = try make(chunks: [.textDelta("重新生成的内容"), .done(finishReason: "stop")],
                             error: ChatError.serverError(status: 500, message: nil))
            return (r.vc, r.viewModel, r.throttle, r.providerBox)
        }()

        // 先跑一轮真的失败的流，产出一条状态为 .failed 且是最后一条的助手消息
        _ = vc.view
        viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)
        #expect(viewModel.state.messages.last?.status == .failed)

        let lastID = try #require(viewModel.state.messages.last?.id)
        let table = try tableView(of: vc)
        let ds = try diffableDataSource(vc)
        let indexPath = try #require(ds.indexPath(for: lastID))
        let cell = try #require(
            ds.tableView(table, cellForRowAt: indexPath) as? AssistantMessageCell)
        #expect(retryButton(in: cell)?.isHidden == false)

        // providerFactory 需要重新准备一个新 provider 供 retryLast() 使用；
        // make() 传入的 chunks/error 是同一份脚本，GatedProvider 每次都会重新创建
        retryButton(in: cell)?.sendActions(for: .touchUpInside)

        #expect(viewModel.state.isStreaming, "点最后一条消息自己的按钮应该正常触发 retryLast")
        // 注意：providerFactory 复用同一份脚本（含 error），retry 这一轮也会以
        // .failed 收尾——这里只关心「retryLast 确实被触发、真的起了新的一轮流」，
        // 不关心这一轮的最终结果，避免测试对 make() 的脚本细节做无关断言
        let retryProvider = try #require(providerBox.current)
        #expect(retryProvider !== firstProvider, "应该是全新的一轮流，而不是复用上一轮的 provider")
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)
    }

    // MARK: - Critical 2：resetBlocks 之后按钮必须立即隐藏

    /// `retryLast()` 把消息状态改成 `.streaming` 并发出 `blocksReset`，
    /// diffable data source 对身份不变的行不会重新请求 cell、不会重新走 `configure()`。
    /// 这里直接对着屏上真实存在的那个 cell 实例断言：`resetBlocks(messageID:)`
    /// 必须立刻把按钮隐藏，不能指望等到这一轮流结束、`invalidateHeight` 触发
    /// `reconfigureItems` 才刷新——那期间按钮会一直留在屏幕上产生死点击。
    @Test("retryLast 之后，屏上残留的重试按钮必须立即隐藏")
    func resetBlocksHidesRetryButtonImmediately() async throws {
        let (vc, viewModel, throttle, providerBox) = try {
            let r = try make(chunks: [.textDelta("半截")],
                             error: ChatError.serverError(status: 500, message: nil))
            return (r.vc, r.viewModel, r.throttle, r.providerBox)
        }()

        _ = vc.view
        let window = attachToWindow(vc)

        viewModel.send("hi")
        let firstProvider = try #require(providerBox.current)
        await firstProvider.deliverNext()
        throttle.fire()
        await firstProvider.finish()
        await waitForStreamEnd(viewModel)
        #expect(viewModel.state.messages.last?.status == .failed)

        let table = try tableView(of: vc)
        table.layoutIfNeeded()
        let assistantID = try #require(viewModel.state.messages.last?.id)
        let ds = try diffableDataSource(vc)
        let indexPath = try #require(ds.indexPath(for: assistantID))
        await waitUntil(table.cellForRow(at: indexPath) != nil)
        let cell = try #require(table.cellForRow(at: indexPath) as? AssistantMessageCell)

        // 前置条件：失败状态下按钮理应可见
        #expect(retryButton(in: cell)?.isHidden == false)

        // retryLast() 内部会先同步发出 blocksReset，VC 的 resetBlocks(messageID:)
        // 应该在这次调用返回之前就已经把同一个 cell 实例上的按钮隐藏掉
        viewModel.retryLast()
        #expect(retryButton(in: cell)?.isHidden == true,
                "resetBlocks 之后必须立即隐藏按钮，不能等流结束才刷新")

        // 收尾：把这一轮 retry 的流跑完，避免留下悬挂的 Task
        let retryProvider = try #require(providerBox.current)
        await retryProvider.deliverNext()
        throttle.fire()
        await retryProvider.finish()
        await waitForStreamEnd(viewModel)

        withExtendedLifetime(window) {}
    }

    // MARK: - C2：思考过程折叠区展开后行高必须重新查询

    /// `ReasoningSectionView.onToggle` 此前从未被任何地方赋值，展开思考过程
    /// 不会让 tableView 重新查询行高，正文会被裁。这里断言接线确实生效：
    /// 展开后再查一次 `heightForRowAt` 应该拿到更大的值，而不是折叠态的旧缓存。
    @Test("展开思考过程后，行高会重新计算变大（C2）")
    func reasoningToggleRecomputesHeight() async throws {
        let (vc, _, _, repository, conversationID, _) = try make(chunks: [])

        try insert(repository, id: "userA", conversationID: conversationID, ordinal: 0,
                  role: .user, content: "问题", status: .completed)
        let longReasoning = String(repeating: "这是很长的思考内容，需要好几行才能显示完整。", count: 20)
        try repository.insertMessage(MessageRecord(
            id: "assistantA", conversationId: conversationID, ordinal: 1,
            roleRaw: ChatRole.assistant.rawValue, content: "回复正文", reasoning: longReasoning,
            statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
            promptTokens: nil, completionTokens: nil,
            createdAt: Date().timeIntervalSince1970))

        _ = vc.view
        let window = attachToWindow(vc)

        let table = try tableView(of: vc)
        let ds = try diffableDataSource(vc)
        let indexPath = try #require(ds.indexPath(for: "assistantA"))
        await waitUntil(table.cellForRow(at: indexPath) != nil)
        let cell = try #require(table.cellForRow(at: indexPath) as? AssistantMessageCell)

        let collapsedHeight = vc.tableView(table, heightForRowAt: indexPath)
        #expect(cell.reasoningExpandedForTesting == false)

        cell.simulateReasoningToggleForTesting()
        #expect(cell.reasoningExpandedForTesting == true)

        let expandedHeight = vc.tableView(table, heightForRowAt: indexPath)
        #expect(expandedHeight > collapsedHeight,
                "onToggle 必须接线到「重算高度 + 惊动 tableView」，否则展开的思考文字会被裁掉")

        withExtendedLifetime(window) {}
    }

    // MARK: - Important 3：说明

    // `UIContextMenuConfiguration` 的 `actionProvider`/`previewProvider` 只在初始化时
    // 写入，没有公开的读取入口（`@testable import` 也拿不到，SDK 头文件里确实没有
    // 对应属性），所以长按菜单「复制」这条 VC 接线没法在测试里从配置对象上把闭包
    // 抠出来再调用验证。核心的判定逻辑——流式期间要不要回退到 accumulatedText——
    // 已经在 ChatViewModelTests.swift 里用
    // `displayTextDuringStreamingReturnsAccumulatedText` /
    // `displayTextAfterFinishMatchesText` 两个纯逻辑用例覆盖了；ChatViewController
    // 侧改动本身只是把 `message.text` 换成 `viewModel.displayText(for: messageID)`
    // 这一行，已用人工审查确认接线正确。
}
