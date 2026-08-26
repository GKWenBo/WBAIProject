import UIKit
import Testing
@testable import WBChatApp_UIKit

/// 覆盖 Task 17 Important 3 的修法本身：ConversationListViewController 左滑删除时，
/// 必须把被删的 id 通过 onDelete 回调交给外层（AppContainer），
/// 外层才有机会判断「删的是不是聊天页正显示的那个会话」并把聊天页切走。
@Suite("会话列表 VC")
@MainActor
struct ConversationListViewControllerTests {

    private func make() throws -> (ConversationListViewController, ConversationListViewModel) {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let viewModel = ConversationListViewModel(repository: repository, settings: AppSettings())
        let vc = ConversationListViewController(viewModel: viewModel)
        return (vc, viewModel)
    }

    @Test("左滑删除会触发 onDelete，且携带的就是被删的那个 id")
    func onDeleteFiresWithDeletedID() throws {
        let (vc, viewModel) = try make()
        _ = vc.view // 触发 viewDidLoad：接上 onItemsChanged -> applySnapshot 这条通路

        // 通过正常入口新建会话，让它经由 onItemsChanged 走到 diffable data source 里，
        // 而不是绕开 VC 直接摆数据——这样才是在测真实的「滑动删除」路径。
        let id = viewModel.createConversation()

        var deletedID: String?
        vc.onDelete = { deletedID = $0 }

        // 表格里此时只有这一条，行号必然是 (0, 0)。
        // tableView(_:trailingSwipeActionsConfigurationForRowAt:) 内部只用 indexPath
        // 经 dataSource 查 id，不依赖传入的 tableView 实例，用哪个占位实例都一样。
        let indexPath = IndexPath(row: 0, section: 0)
        let config = try #require(
            vc.tableView(UITableView(), trailingSwipeActionsConfigurationForRowAt: indexPath))
        let deleteAction = try #require(config.actions.first { $0.style == .destructive })

        deleteAction.handler(deleteAction, UIView()) { _ in }

        #expect(deletedID == id)
        // 顺带确认 DB 真的删了（onDelete 是在 viewModel.delete(id:) 之后触发的）
        #expect(!viewModel.items.contains { $0.id == id })
    }
}
