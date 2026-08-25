import Foundation
import GRDB

protocol ChatRepository: AnyObject {
    func allConversations() throws -> [ConversationRecord]
    func observeConversations(_ onChange: @escaping ([ConversationRecord]) -> Void) -> AnyDatabaseCancellable
    @discardableResult
    func createConversation(title: String, provider: ProviderKind, model: String) throws -> ConversationRecord
    func renameConversation(id: String, title: String) throws
    func deleteConversation(id: String) throws
    func messages(in conversationId: String) throws -> [MessageRecord]
    func insertMessage(_ record: MessageRecord) throws
    func updateMessage(_ record: MessageRecord) throws
    func touchConversation(id: String) throws
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
    func observeConversations(_ onChange: @escaping ([ConversationRecord]) -> Void) -> AnyDatabaseCancellable {
        let observation = ValueObservation.tracking { db in
            try ConversationRecord.order(Column("updatedAt").desc).fetchAll(db)
        }
        return observation.start(in: queue,
                                 scheduling: .async(onQueue: .main),
                                 onError: { _ in },
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
