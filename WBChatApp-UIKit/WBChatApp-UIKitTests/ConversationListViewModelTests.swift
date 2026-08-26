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
    func deleteConversation() throws {
        let (viewModel, _) = try make()
        viewModel.start()
        let id = viewModel.createConversation()
        viewModel.delete(id: id)
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

    @Test("列表变化触发回调")
    func changeCallbackFires() throws {
        let (viewModel, _) = try make()
        var callbackCount = 0
        viewModel.onItemsChanged = { _ in callbackCount += 1 }
        viewModel.start()
        _ = viewModel.createConversation()
        #expect(callbackCount > 0)
    }
}
