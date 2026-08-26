import Foundation
import GRDB

@MainActor
final class ConversationListViewModel {

    struct Item: Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    private(set) var items: [Item] = [] {
        didSet {
            guard items != oldValue else { return }
            onItemsChanged?(items)
        }
    }

    var onItemsChanged: (([Item]) -> Void)?

    private let repository: ChatRepository
    private let settings: AppSettings
    /// 必须持有，否则 ARC 释放时观察会立即静默取消
    private var observation: AnyDatabaseCancellable?

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    init(repository: ChatRepository, settings: AppSettings) {
        self.repository = repository
        self.settings = settings
    }

    /// 用 ValueObservation 订阅，数据库一变列表自动刷新
    func start() {
        reload()
        observation = repository.observeConversations(
            onError: { error in
                // GRDB 语义：onError 触发后观察即终止、不会自动恢复，也不会再有后续 onChange。
                // 这里至少打日志留下诊断信号，避免会话列表永久静默停止刷新却毫无察觉。
                print("[ConversationListViewModel] 会话列表观察出错，已终止: \(error)")
            },
            onChange: { [weak self] records in
                self?.items = records.map(Self.item(from:))
            })
    }

    @discardableResult
    func createConversation() -> String {
        let record = try? repository.createConversation(title: "新对话",
                                                        provider: settings.provider,
                                                        model: settings.model)
        reload()
        return record?.id ?? ""
    }

    func delete(id: String) {
        try? repository.deleteConversation(id: id)
        reload()
    }

    func rename(id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? repository.renameConversation(id: id, title: trimmed)
        reload()
    }

    private func reload() {
        items = ((try? repository.allConversations()) ?? []).map(Self.item(from:))
    }

    private static func item(from record: ConversationRecord) -> Item {
        Item(id: record.id,
             title: record.title,
             subtitle: formatter.string(from: Date(timeIntervalSince1970: record.updatedAt)))
    }
}
