import Testing
import Foundation
import GRDB
@testable import WBChatApp_UIKit

@Suite("生成持久化")
struct GenerationPersistenceTests {
    @Test("重启修复遗留生成状态并保留快照")
    func recoversStreamingSnapshot() throws {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let conversation = try repository.createConversation(title: "恢复", provider: .deepSeek, model: "test")
        let record = MessageRecord(id: "reply", conversationId: conversation.id, ordinal: 0,
            roleRaw: "assistant", content: "已收到的正文", reasoning: "思考", statusRaw: "streaming",
            errorMessage: nil, promptTokens: nil, completionTokens: nil, createdAt: 1)
        try repository.insertMessage(record)
        try repository.recoverInterruptedGenerations()
        let loaded = try #require(repository.messages(in: conversation.id).first)
        #expect(loaded.statusRaw == "interrupted")
        #expect(loaded.content == "已收到的正文")
        #expect(loaded.reasoning == "思考")
    }
    @Test("旧快照、旧生成身份、终态后的写入均被拒绝")
    func rejectsStaleAndTerminalWrites() throws {
        let repository = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
        let id = try repository.createConversation(title: "CAS", provider: .deepSeek, model: "test").id
        var record = try #require(repository.beginTurn(conversationID: id, text: "hi", generationID: "first").last)
        record.snapshotSequence = 2
        record.content = "新版"
        #expect(try repository.saveGeneration(record))
        record.snapshotSequence = 1
        record.content = "旧版"
        #expect(try !repository.saveGeneration(record))
        record.snapshotSequence = 3
        record.generationID = "stale"
        #expect(try !repository.saveGeneration(record))
        record.generationID = "first"
        record.statusRaw = "stopped"
        record.content = "终态"
        #expect(try repository.saveGeneration(record))
        record.snapshotSequence = 4
        record.statusRaw = "streaming"
        #expect(try !repository.saveGeneration(record))
        #expect(try repository.messages(in: id).last?.content == "终态")
    }

    @Test("助手占位写入失败回滚用户消息与会话更新")
    func transactionRollsBackBothMessages() throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        let repository = GRDBChatRepository(queue: queue)
        let id = try repository.createConversation(title: "事务", provider: .deepSeek, model: "test").id
        try queue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_assistant BEFORE INSERT ON message WHEN NEW.roleRaw = 'assistant' BEGIN SELECT RAISE(ABORT, 'disk failure'); END")
        }
        #expect(throws: (any Error).self) { try repository.beginTurn(conversationID: id, text: "hi", generationID: "g") }
        #expect(try repository.messages(in: id).isEmpty)
    }

    @Test("旧版磁盘数据库升级保留历史并增加快照字段")
    func migratesV1Database() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let old = try DatabaseQueue(path: url.path)
            try old.write { db in
                try db.execute(sql: """
                    CREATE TABLE grdb_migrations(identifier TEXT NOT NULL PRIMARY KEY);
                    INSERT INTO grdb_migrations VALUES ('v1_创建会话与消息表');
                    CREATE TABLE conversation(id TEXT PRIMARY KEY, title TEXT NOT NULL, providerRaw TEXT NOT NULL, model TEXT NOT NULL, createdAt DOUBLE NOT NULL, updatedAt DOUBLE NOT NULL);
                    CREATE TABLE message(id TEXT PRIMARY KEY, conversationId TEXT NOT NULL REFERENCES conversation(id) ON DELETE CASCADE, ordinal INTEGER NOT NULL, roleRaw TEXT NOT NULL, content TEXT NOT NULL, reasoning TEXT, statusRaw TEXT NOT NULL, errorMessage TEXT, promptTokens INTEGER, completionTokens INTEGER, createdAt DOUBLE NOT NULL);
                    INSERT INTO conversation VALUES ('c', '旧会话', 'deepSeek', 'm', 1, 1);
                    INSERT INTO message VALUES ('m', 'c', 0, 'assistant', '旧正文', NULL, 'streaming', NULL, NULL, NULL, 1);
                    """)
            }
        }
        let migrated = GRDBChatRepository(queue: try AppDatabase.makeQueue(at: url))
        try migrated.recoverInterruptedGenerations()
        let record = try #require(migrated.messages(in: "c").first)
        #expect(record.content == "旧正文")
        #expect(record.status == .interrupted)
        #expect(record.snapshotSequence == 0)
    }

}
