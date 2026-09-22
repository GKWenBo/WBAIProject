import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("会话列表 ViewModel")
@MainActor
struct ConversationListViewModelTests {

    private func make() throws -> (ConversationListViewModel, GRDBChatRepository) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let viewModel = ConversationListViewModel(repository: repository, settings: AppSettings())
        return (viewModel, repository)
    }

    @Test("start 后读到已有会话")
    func startLoadsExisting() throws {
        let (viewModel, repository) = try make()
        _ = try repository.createConversation(title: "已有会话", provider: .deepSeek, model: "m")
        viewModel.start()
        #expect(viewModel.items.contains { $0.title == "已有会话" })
    }

    @Test("新建会话返回新 id 并出现在列表")
    func createConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        #expect(viewModel.items.contains { $0.id == id })
    }

    @Test("删除会话后从列表消失")
    func deleteConversation() async throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        try await viewModel.delete(id: id)
        #expect(!viewModel.items.contains { $0.id == id })
    }

    @Test("重命名会话")
    func renameConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        viewModel.rename(id: id, to: "改过的名字")
        #expect(viewModel.items.first { $0.id == id }?.title == "改过的名字")
    }

    @Test("列表变化触发回调：精确次数")
    func changeCallbackFires() throws {
        let (viewModel, _) = try make()
        var callbackCount = 0
        viewModel.onItemsChanged = { _ in callbackCount += 1 }

        viewModel.start()
        // make() 用的是全新的空库：start() 内部 reload() 把 items 从初始值 [] 变成
        // 还是 [] ——没有变化，didSet 的 guard 会拦掉，这里不应该触发回调。
        #expect(callbackCount == 0)

        _ = viewModel.createConversation()
        // createConversation() 内部同步调用一次 reload()，items 从 [] 变成 [新会话]，
        // 触发且只触发这一次回调（observeConversations 对应这次写入的异步推送这时还没到达）。
        #expect(callbackCount == 1)
    }

    /// 轮询等待，直到条件成立或超时（用于等待 ValueObservation 的异步回调到达主线程）。
    /// 写法参照 ChatRepositoryTests 里 observeConversations 的异步观察测试。
    private func waitUntil(timeoutSeconds: Double = 2,
                           condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @Test("绕开 ViewModel 直接写库，验证 observeConversations 的异步推送能自动刷新列表")
    func directWriteTriggersAutoRefreshViaObservation() async throws {
        let (viewModel, repository) = try make()
        var refreshCount = 0
        viewModel.onItemsChanged = { _ in refreshCount += 1 }

        // expectedCount = 1：start() 时库是空的，reload() 前后 items 都是 []，不触发回调；
        // 真正会触发的这一次只能来自下面「绕开 viewModel 直接写库」之后，
        // observeConversations 的异步 onChange ——如果这条通路根本没接上，
        // 这个 confirmation 会在超时后失败，而不是被 waitUntil 悄悄放过。
        // 不需要额外 withExtendedLifetime 持有 cancellable：ConversationListViewModel
        // 自己的 `observation` 属性已经在持有它，只要 viewModel 这个局部变量在测试期间存活即可。
        await confirmation("列表因 observeConversations 的异步推送而刷新", expectedCount: 1) { confirm in
            viewModel.start()
            #expect(refreshCount == 0)

            // 特意绕开 viewModel.createConversation()（它内部会同步 reload()，
            // 会掩盖 observeConversations 这条通路本身到底有没有工作）：
            // 直接对 repository 写库，items 唯一可能的更新来源就是异步 onChange。
            _ = try? repository.createConversation(title: "直接写库", provider: .deepSeek, model: "m")

            await waitUntil { refreshCount >= 1 }
            if refreshCount >= 1 { confirm() }
        }

        #expect(viewModel.items.contains { $0.title == "直接写库" })
    }
}
