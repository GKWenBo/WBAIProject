import Foundation
import GRDB

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
