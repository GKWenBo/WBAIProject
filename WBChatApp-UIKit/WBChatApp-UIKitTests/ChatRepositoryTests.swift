import Foundation
import GRDB
import Testing
@testable import WBChatApp_UIKit

@Suite("持久化")
struct ChatRepositoryTests {

    private func makeRepository() throws -> GRDBChatRepository {
        GRDBChatRepository(queue: try AppDatabase.makeQueue(at: nil))
    }

    private func message(_ id: String, conversation: String, ordinal: Int,
                         role: ChatRole = .user, content: String = "内容") -> MessageRecord {
        MessageRecord(id: id, conversationId: conversation, ordinal: ordinal,
                      roleRaw: role.rawValue, content: content, reasoning: nil,
                      statusRaw: MessageStatus.completed.rawValue, errorMessage: nil,
                      promptTokens: nil, completionTokens: nil,
                      createdAt: Date().timeIntervalSince1970)
    }

    @Test("建库后表结构可用")
    func migrationCreatesTables() throws {
        let queue = try AppDatabase.makeQueue(at: nil)
        // GRDB 的 read(_:) 存在同步/异步两个重载，同步版本带 @_disfavoredOverload。
        // 在此处若不显式标注闭包签名，Swift Testing 的 #expect 宏展开会导致编译器
        // 报 "errors thrown from here are not handled"（已用最小复现验证是宏与
        // 重载消歧的交互问题，与业务逻辑无关），显式写出 `(db: Database) throws in` 可规避。
        try queue.read { (db: Database) throws in
            #expect(try db.tableExists("conversation"))
            #expect(try db.tableExists("message"))
        }
    }

    @Test("创建并读回会话")
    func createAndFetchConversation() throws {
        let repository = try makeRepository()
        let created = try repository.createConversation(title: "新对话", provider: .deepSeek,
                                                        model: "deepseek-chat")
        let all = try repository.allConversations()
        #expect(all.count == 1)
        #expect(all[0].id == created.id)
        #expect(all[0].title == "新对话")
        #expect(all[0].providerRaw == ProviderKind.deepSeek.rawValue)
    }

    @Test("会话按 updatedAt 倒序")
    func conversationsSortedByUpdatedAt() throws {
        let repository = try makeRepository()
        let first = try repository.createConversation(title: "旧", provider: .deepSeek, model: "m")
        _ = try repository.createConversation(title: "新", provider: .deepSeek, model: "m")
        try repository.touchConversation(id: first.id)
        #expect(try repository.allConversations().first?.title == "旧")
    }

    @Test("重命名会话")
    func renameConversation() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "旧名", provider: .openAI, model: "m")
        try repository.renameConversation(id: conversation.id, title: "新名")
        #expect(try repository.allConversations()[0].title == "新名")
    }

    @Test("删除会话级联删除消息")
    func deleteCascades() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        try repository.insertMessage(message("m1", conversation: conversation.id, ordinal: 0))
        try repository.deleteConversation(id: conversation.id)
        #expect(try repository.allConversations().isEmpty)
        #expect(try repository.messages(in: conversation.id).isEmpty)
    }

    @Test("消息按 ordinal 升序返回")
    func messagesSortedByOrdinal() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        try repository.insertMessage(message("m2", conversation: conversation.id, ordinal: 1, content: "第二"))
        try repository.insertMessage(message("m1", conversation: conversation.id, ordinal: 0, content: "第一"))
        #expect(try repository.messages(in: conversation.id).map(\.content) == ["第一", "第二"])
    }

    @Test("更新消息内容与状态")
    func updateMessage() throws {
        let repository = try makeRepository()
        let conversation = try repository.createConversation(title: "会话", provider: .deepSeek, model: "m")
        var record = message("m1", conversation: conversation.id, ordinal: 0, role: .assistant)
        record.statusRaw = MessageStatus.streaming.rawValue
        try repository.insertMessage(record)

        record.content = "完整回复"
        record.statusRaw = MessageStatus.completed.rawValue
        record.completionTokens = 42
        try repository.updateMessage(record)

        let fetched = try #require(try repository.messages(in: conversation.id).first)
        #expect(fetched.content == "完整回复")
        #expect(fetched.status == .completed)
        #expect(fetched.completionTokens == 42)
    }

    @Test("role 与 status 便利属性可用")
    func convenienceAccessors() {
        let record = message("m1", conversation: "c", ordinal: 0, role: .assistant)
        #expect(record.role == .assistant)
        #expect(record.status == .completed)
    }

    @Test("Keychain 存取删")
    func keychainRoundTrip() throws {
        let key = "test.api.key.\(UUID().uuidString)"
        try KeychainStore.save("sk-secret", for: key)
        #expect(KeychainStore.read(key) == "sk-secret")
        try KeychainStore.save("sk-updated", for: key)
        #expect(KeychainStore.read(key) == "sk-updated")
        try KeychainStore.delete(key)
        #expect(KeychainStore.read(key) == nil)
    }
}
