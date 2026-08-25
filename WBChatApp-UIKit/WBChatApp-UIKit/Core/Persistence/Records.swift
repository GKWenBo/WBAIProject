import Foundation
import GRDB

/// 消息在生命周期中的状态：流式中 / 已完成 / 被用户中止 / 失败
enum MessageStatus: String, Codable, Sendable {
    case streaming, completed, stopped, failed
}

/// 会话记录，对应 `conversation` 表
struct ConversationRecord: Codable, FetchableRecord, MutablePersistableRecord,
                           Identifiable, Equatable, Sendable {
    static let databaseTableName = "conversation"

    var id: String
    var title: String
    var providerRaw: String
    var model: String
    var createdAt: Double
    var updatedAt: Double

    var provider: ProviderKind { ProviderKind(rawValue: providerRaw) ?? .deepSeek }
}

/// 消息记录，对应 `message` 表
struct MessageRecord: Codable, FetchableRecord, MutablePersistableRecord,
                      Identifiable, Equatable, Sendable {
    static let databaseTableName = "message"

    var id: String
    var conversationId: String
    /// 会话内的顺序，从 0 递增
    var ordinal: Int
    var roleRaw: String
    var content: String
    var reasoning: String?
    var statusRaw: String
    var errorMessage: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var createdAt: Double

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
    var status: MessageStatus { MessageStatus(rawValue: statusRaw) ?? .completed }
}
