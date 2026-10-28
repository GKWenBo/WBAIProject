import Foundation
import GRDB

/// 抽屉里的会话列表：订阅数据库与生成状态，提供新建、删除、重命名。
@MainActor
final class ConversationListViewModel {

    /// 列表一行的展示数据
    struct Item: Equatable {
        let id: String
        let title: String
        /// 更新时间，正在生成时显示"生成中…"
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
    /// 用来查询会话是否在生成，以及走协调器删除（会先取消生成）
    private let generations: ChatGenerationCoordinator?
    /// 生成状态订阅句柄，deinit 时注销
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

    /// 新建会话并返回 id，失败返回空串
    @discardableResult
    func createConversation() -> String {
        let record = try? repository.createConversation(title: "新对话",
                                                        provider: settings.provider,
                                                        model: settings.model)
        reload()
        return record?.id ?? ""
    }

    /// 删除会话；有协调器时由它先取消生成再删库
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

    /// 记录 → 展示数据，叠加生成中状态
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
