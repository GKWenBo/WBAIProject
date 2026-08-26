import Foundation
import GRDB
import UIKit

/// 依赖组装。整个工程里唯一知道具体实现类型的地方。
final class AppContainer {

    static let shared = AppContainer()

    let settings = AppSettings()
    let repository: ChatRepository

    /// 渲染相关的对象全局共用，缓存才能跨消息复用
    let renderer = AttributedRenderer()
    let cache = AttributedCache()
    let pool = BlockViewPool()

    private init() {
        do {
            let queue = try AppDatabase.makeQueue(at: try AppDatabase.defaultURL())
            repository = GRDBChatRepository(queue: queue)
        } catch {
            // 建库失败时退回内存库，保证 App 仍可运行
            repository = GRDBChatRepository(queue: try! AppDatabase.makeQueue(at: nil))
        }
    }

    /// 没配 Key 就走演示模式，保证 App 开箱可用
    func makeProvider() -> ChatProvider {
        guard settings.hasAPIKey else { return MockProvider() }
        return NetworkChatProvider(config: settings.currentConfig)
    }

    /// ChatViewModel 与 ChatViewController 都是主线程隔离的，工厂方法也要标注
    @MainActor
    func makeChatViewModel(conversationID: String) -> ChatViewModel {
        ChatViewModel(conversationID: conversationID,
                      repository: repository,
                      providerFactory: { [weak self] in
                          self?.makeProvider() ?? MockProvider()
                      },
                      systemPrompt: settings.systemPrompt,
                      model: settings.model,
                      throttle: DisplayLinkThrottle())
    }

    @MainActor
    func makeChatViewController(conversationID: String) -> ChatViewController {
        ChatViewController(viewModel: makeChatViewModel(conversationID: conversationID),
                           renderer: renderer,
                           cache: cache,
                           pool: pool)
    }

    /// 启动时取最近一个会话，没有就新建
    func currentOrNewConversationID() -> String {
        if let latest = try? repository.allConversations().first {
            return latest.id
        }
        let created = try? repository.createConversation(title: "新对话",
                                                         provider: settings.provider,
                                                         model: settings.model)
        return created?.id ?? UUID().uuidString
    }
}

extension AppContainer {
    @MainActor
    func makeSettingsViewController() -> SettingsViewController {
        SettingsViewController(viewModel: SettingsViewModel(settings: settings))
    }
}

extension AppContainer {

    /// 抽屉 + 聊天页的完整根控制器
    @MainActor
    func makeRootViewController() -> UIViewController {
        let listViewModel = ConversationListViewModel(repository: repository, settings: settings)
        let list = ConversationListViewController(viewModel: listViewModel)

        // 记录聊天页当前显示的会话 id：删除会话时要判断删的是不是这一个，
        // 是的话就把聊天页切走，否则僵尸聊天页发消息会因外键约束静默丢库（insertMessage 用了 try?）
        var currentConversationID = currentOrNewConversationID()

        let chat = makeChatViewController(conversationID: currentConversationID)
        let navigation = UINavigationController(rootViewController: chat)
        let drawer = DrawerContainerViewController(drawer: list, content: navigation)

        list.onSelect = { [weak drawer, weak self] conversationID in
            guard let self, let drawer else { return }
            currentConversationID = conversationID
            let newChat = self.makeChatViewController(conversationID: conversationID)
            newChat.navigationItem.leftBarButtonItem = self.makeMenuItem(drawer: drawer)
            drawer.setContent(UINavigationController(rootViewController: newChat))
            drawer.closeDrawer()
        }
        list.onOpenSettings = { [weak drawer, weak self] in
            guard let self, let drawer else { return }
            let settingsViewController = self.makeSettingsViewController()
            drawer.present(UINavigationController(rootViewController: settingsViewController),
                           animated: true)
        }
        list.onDelete = { [weak drawer, weak self] deletedID in
            guard let self, let drawer, deletedID == currentConversationID else { return }
            // 聊天页正显示的会话被删了：换到最近的一个会话（没有就新建），
            // 避免聊天页停留在一个 DB 里已经不存在的 conversationId 上
            let newID = self.currentOrNewConversationID()
            currentConversationID = newID
            let newChat = self.makeChatViewController(conversationID: newID)
            newChat.navigationItem.leftBarButtonItem = self.makeMenuItem(drawer: drawer)
            drawer.setContent(UINavigationController(rootViewController: newChat))
        }

        chat.navigationItem.leftBarButtonItem = makeMenuItem(drawer: drawer)
        return drawer
    }

    @MainActor
    private func makeMenuItem(drawer: DrawerContainerViewController) -> UIBarButtonItem {
        let item = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal"),
                                   style: .plain,
                                   target: drawer,
                                   action: #selector(DrawerContainerViewController.toggleDrawer))
        item.accessibilityIdentifier = "chat.menu"
        return item
    }
}
