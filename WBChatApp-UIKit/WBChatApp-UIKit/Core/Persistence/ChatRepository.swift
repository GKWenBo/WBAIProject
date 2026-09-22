import Foundation
import GRDB

protocol ChatRepository: AnyObject {
    func allConversations() throws -> [ConversationRecord]
    /// 订阅会话列表变化。
    /// - Parameter onError: 观察内部出错时的回调（可选）。GRDB 的语义是 onError 一旦触发，
    ///   观察即终止，不会自动恢复，也不会再有后续 onChange，因此调用方应据此提示或重新订阅。
    /// - Parameter onChange: 会话列表变化时的回调，订阅后会立即推送一次当前值。
    /// - Returns: 观察句柄。**调用方必须持有它**，一旦被 ARC 释放，观察会被立即静默取消。
    func observeConversations(
        onError: ((Error) -> Void)?,
        onChange: @escaping ([ConversationRecord]) -> Void
    ) -> AnyDatabaseCancellable
    @discardableResult
    func createConversation(title: String, provider: ProviderKind, model: String) throws -> ConversationRecord
    func renameConversation(id: String, title: String) throws
    func deleteConversation(id: String) throws
    func messages(in conversationId: String) throws -> [MessageRecord]
    func insertMessage(_ record: MessageRecord) throws
    func updateMessage(_ record: MessageRecord) throws
    func touchConversation(id: String) throws
    func beginTurn(conversationID: String, text: String, generationID: String) throws -> [MessageRecord]
    func beginRegeneration(conversationID: String, messageID: String, generationID: String) throws -> [MessageRecord]
    @discardableResult func saveGeneration(_ record: MessageRecord) throws -> Bool
    func recoverInterruptedGenerations() throws
}

final class GRDBChatRepository: ChatRepository {

    private let queue: DatabaseQueue

    init(queue: DatabaseQueue) {
        self.queue = queue
    }

    // MARK: - 会话

    func allConversations() throws -> [ConversationRecord] {
        try queue.read { db in
            try ConversationRecord
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    /// 数据库变化自动推送。会话列表用它，免去手动刷新。
    /// 注意：返回的观察句柄必须被调用方持有，否则 ARC 释放时观察会立即取消。
    func observeConversations(
        onError: ((Error) -> Void)? = nil,
        onChange: @escaping ([ConversationRecord]) -> Void
    ) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try ConversationRecord.order(Column("updatedAt").desc).fetchAll(db)
        }
        return observation.start(in: queue,
                                 scheduling: .async(onQueue: .main),
                                 onError: { error in
                                     // GRDB 语义：onError 触发后观察即终止，不会自动恢复，
                                     // 也不会再有后续 onChange。这里不能吞掉错误，
                                     // 否则会话列表会永久静默停止刷新且无任何诊断信号。
                                     print("[ChatRepository] observeConversations 观察出错，已终止: \(error)")
                                     onError?(error)
                                 },
                                 onChange: onChange)
    }

    @discardableResult
    func createConversation(title: String, provider: ProviderKind,
                            model: String) throws -> ConversationRecord {
        let now = Date().timeIntervalSince1970
        var record = ConversationRecord(id: UUID().uuidString,
                                        title: title,
                                        providerRaw: provider.rawValue,
                                        model: model,
                                        createdAt: now,
                                        updatedAt: now)
        try queue.write { db in try record.insert(db) }
        return record
    }

    func renameConversation(id: String, title: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE conversation SET title = ?, updatedAt = ? WHERE id = ?",
                           arguments: [title, Date().timeIntervalSince1970, id])
        }
    }

    func deleteConversation(id: String) throws {
        _ = try queue.write { db in
            try ConversationRecord.deleteOne(db, key: id)
        }
    }

    /// 有新消息时把会话顶到列表最前
    func touchConversation(id: String) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?",
                           arguments: [Date().timeIntervalSince1970, id])
        }
    }

    // MARK: - 消息

    func messages(in conversationId: String) throws -> [MessageRecord] {
        try queue.read { db in
            try MessageRecord
                .filter(Column("conversationId") == conversationId)
                .order(Column("ordinal").asc)
                .fetchAll(db)
        }
    }

    func insertMessage(_ record: MessageRecord) throws {
        var record = record
        try queue.write { db in try record.insert(db) }
    }

    func updateMessage(_ record: MessageRecord) throws {
        try queue.write { db in try record.update(db) }
    }
}


extension GRDBChatRepository {
    func beginTurn(conversationID: String, text: String, generationID: String) throws -> [MessageRecord] {
        try queue.write { db in
            let now = Date().timeIntervalSince1970
            let next = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(ordinal), -1) + 1 FROM message WHERE conversationId = ?",
                                       arguments: [conversationID]) ?? 0
            var user = MessageRecord(id: UUID().uuidString, conversationId: conversationID, ordinal: next,
                roleRaw: "user", content: text, reasoning: nil, statusRaw: "completed", errorMessage: nil,
                promptTokens: nil, completionTokens: nil, createdAt: now)
            var assistant = MessageRecord(id: UUID().uuidString, conversationId: conversationID, ordinal: next + 1,
                roleRaw: "assistant", content: "", reasoning: nil, statusRaw: "streaming", errorMessage: nil,
                promptTokens: nil, completionTokens: nil, createdAt: now, generationID: generationID)
            try user.insert(db)
            try assistant.insert(db)
            try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?", arguments: [now, conversationID])
            return try MessageRecord.filter(Column("conversationId") == conversationID).order(Column("ordinal")).fetchAll(db)
        }
    }

    func beginRegeneration(conversationID: String, messageID: String, generationID: String) throws -> [MessageRecord] {
        try queue.write { db in
            let records = try MessageRecord.filter(Column("conversationId") == conversationID).order(Column("ordinal")).fetchAll(db)
            guard var last = records.last, last.id == messageID, last.role == .assistant else { throw ChatError.storage }
            last.generationID = generationID
            last.snapshotSequence = 0
            last.checkpointAt = nil
            last.statusRaw = MessageStatus.streaming.rawValue
            last.errorMessage = nil
            last.endReason = nil
            try last.update(db)
            try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?",
                           arguments: [Date().timeIntervalSince1970, conversationID])
            return Array(records.dropLast()) + [last]
        }
    }

    @discardableResult
    func saveGeneration(_ record: MessageRecord) throws -> Bool {
        try queue.write { db in
            guard let current = try MessageRecord.fetchOne(db, key: record.id),
                  current.generationID == record.generationID,
                  current.status == .streaming,
                  record.snapshotSequence > current.snapshotSequence else { return false }
            try record.update(db)
            if record.status != .streaming {
                try db.execute(sql: "UPDATE conversation SET updatedAt = ? WHERE id = ?",
                               arguments: [Date().timeIntervalSince1970, record.conversationId])
            }
            return true
        }
    }

    func recoverInterruptedGenerations() throws {
        try queue.write { db in
            try db.execute(sql: """
                UPDATE message SET statusRaw = 'interrupted', endReason = 'processRestart',
                    errorMessage = '上次生成已中断，可重新生成', checkpointAt = ?
                WHERE statusRaw = 'streaming'
                """, arguments: [Date().timeIntervalSince1970])
        }
    }
}

/// 所有生成写入在独立串行队列执行；顺序与数据库 CAS 共同保护终态。
final class GenerationStore: @unchecked Sendable {
    private let repository: ChatRepository
    private let queue = DispatchQueue(label: "chat.generation.persistence", qos: .utility)

    init(repository: ChatRepository) { self.repository = repository }

    func schedule<T>(_ operation: @escaping (ChatRepository) throws -> T,
                     completion: @escaping (Result<T, Error>) -> Void) {
        queue.async { completion(Result { try operation(self.repository) }) }
    }

    func perform<T>(_ operation: @escaping (ChatRepository) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation(self.repository) })
            }
        }
    }
}
