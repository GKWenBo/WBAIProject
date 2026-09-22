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
    private let generations: ChatGenerationCoordinator?
    private var activityObservation: UUID?
    /// 必须持有，否则 ARC 释放时观察会立即静默取消
    private var observation: AnyDatabaseCancellable?

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    init(repository: ChatRepository, settings: AppSettings, generations: ChatGenerationCoordinator? = nil) {
        self.repository = repository
        self.settings = settings
        self.generations = generations
    }

    /// 用 ValueObservation 订阅，数据库一变列表自动刷新
    func start() {
        reload()
        if activityObservation == nil { activityObservation = generations?.observeActivity { [weak self] in self?.reload() } }
        observation = repository.observeConversations(
            onError: { error in
                // GRDB 语义：onError 触发后观察即终止、不会自动恢复，也不会再有后续 onChange。
                // 这里至少打日志留下诊断信号，避免会话列表永久静默停止刷新却毫无察觉。
                print("[ConversationListViewModel] 会话列表观察出错，已终止: \(error)")
            },
            onChange: { [weak self] records in
                self?.items = records.map { self?.item(from: $0) ?? Self.basicItem(from: $0) }
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

    func delete(id: String) async throws {
        if let generations { try await generations.deleteConversation(id) }
        else { try await GenerationStore(repository: repository).perform { try $0.deleteConversation(id: id) } }
        reload()
    }

    func rename(id: String, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? repository.renameConversation(id: id, title: trimmed)
        reload()
    }

    private func reload() {
        items = ((try? repository.allConversations()) ?? []).map { item(from: $0) }
    }

    deinit {
        if let activityObservation, let generations {
            Task { @MainActor in generations.removeActivityObserver(activityObservation) }
        }
    }

    private func item(from record: ConversationRecord) -> Item {
        let basic = Self.basicItem(from: record)
        return Item(id: basic.id, title: basic.title,
                    subtitle: generations?.isGenerating(record.id) == true ? "生成中…" : basic.subtitle)
    }

    private static func basicItem(from record: ConversationRecord) -> Item {
        Item(id: record.id,
             title: record.title,
             subtitle: formatter.string(from: Date(timeIntervalSince1970: record.updatedAt)))
    }
}
