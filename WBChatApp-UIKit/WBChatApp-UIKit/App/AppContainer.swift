import Foundation
import GRDB
import UIKit

/// 依赖组装。整个工程里唯一知道具体实现类型的地方。
@MainActor
final class AppContainer {

    /// 服务商、模型、系统提示词等用户配置
    let settings = AppSettings()
    /// 会话与消息的持久化入口
    let repository: ChatRepository

    /// 渲染相关的对象全局共用，缓存才能跨消息复用
    let renderer = AttributedRenderer()
    let cache = AttributedCache()
    let pool = BlockViewPool()
    /// 无视图测高用的 TextKit 2 栈，共享一套避免每个块视图各建一份
    let measurer = TextKitMeasurer()

    /// 全局唯一的生成协调器：持有所有会话的流式任务，切换会话不会中断生成
    lazy var generations = ChatGenerationCoordinator(repository: repository,
        providerFactory: { [weak self] in self?.makeProvider() ?? MockProvider() },
        configProvider: { [weak self] in (self?.settings.model ?? "", self?.settings.systemPrompt) },
        background: UIKitBackgroundExecution())

    private init(repository: ChatRepository) { self.repository = repository }

    /// 后台线程打开数据库，并把上次被杀进程时残留的"生成中"消息标记为中断
    static func open() async throws -> AppContainer {
        let repository = try await Task.detached(priority: .userInitiated) {
            let queue = try AppDatabase.makeQueue(at: AppDatabase.defaultURL())
            let repository = GRDBChatRepository(queue: queue)
            try repository.recoverInterruptedGenerations()
            return repository
        }.value
        return AppContainer(repository: repository)
    }

    /// 没配 Key 就走演示模式，保证 App 开箱可用
    func makeProvider() -> ChatProvider {
        guard settings.hasAPIKey else { return MockProvider() }
        return NetworkChatProvider(config: settings.currentConfig)
    }

    /// ChatViewModel 与 ChatViewController 都是主线程隔离的，工厂方法也要标注
    @MainActor
    func makeChatViewModel(conversationID: String) -> ChatViewModel {
        ChatViewModel(conversationID: conversationID, coordinator: generations, throttle: DisplayLinkThrottle())
    }

    @MainActor
    func makeChatViewController(conversationID: String) -> ChatViewController {
        ChatViewController(viewModel: makeChatViewModel(conversationID: conversationID),
                           renderer: renderer,
                           cache: cache,
                           pool: pool,
                           measurer: measurer)
    }

    /// 启动时取最近一个会话，没有就新建
    func currentOrNewConversationID() throws -> String {
        if let latest = try repository.allConversations().first {
            return latest.id
        }
        let created = try repository.createConversation(title: "新对话",
                                                         provider: settings.provider,
                                                         model: settings.model)
        return created.id
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
    func makeRootViewController() throws -> UIViewController {
        let listViewModel = ConversationListViewModel(repository: repository, settings: settings, generations: generations)
        let list = ConversationListViewController(viewModel: listViewModel)

        // 记录聊天页当前显示的会话 id：删除会话时要判断删的是不是这一个，
        // 是的话就把聊天页切走，否则僵尸聊天页发消息会因外键约束静默丢库（insertMessage 用了 try?）
        var currentConversationID = try currentOrNewConversationID()

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
            guard let newID = try? self.currentOrNewConversationID() else {
                let empty = UIViewController()
                empty.view.backgroundColor = .systemBackground
                drawer.setContent(empty)
                let alert = UIAlertController(title: "无法加载会话", message: "本地存储暂时不可用，请重新打开应用后重试", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                drawer.present(alert, animated: true)
                return
            }
            currentConversationID = newID
            let newChat = self.makeChatViewController(conversationID: newID)
            newChat.navigationItem.leftBarButtonItem = self.makeMenuItem(drawer: drawer)
            drawer.setContent(UINavigationController(rootViewController: newChat))
        }

        chat.navigationItem.leftBarButtonItem = makeMenuItem(drawer: drawer)
        return drawer
    }

    /// 导航栏左侧的抽屉开关按钮
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
