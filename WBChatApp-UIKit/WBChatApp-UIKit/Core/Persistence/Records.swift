import Foundation
import GRDB

/// 消息在生命周期中的状态：流式中 / 已完成 / 被用户中止 / 失败 / 进程退出导致中断
enum MessageStatus: String, Codable, Sendable {
    case streaming, completed, stopped, failed, interrupted
}

/// 会话记录，对应 `conversation` 表
struct ConversationRecord: Codable, FetchableRecord, MutablePersistableRecord,
                           Identifiable, Equatable, Sendable {
    static let databaseTableName = "conversation"

    var id: String
    var title: String
    /// `ProviderKind` 的 rawValue
    var providerRaw: String
    var model: String
    /// 时间戳均为 timeIntervalSince1970
    var createdAt: Double
    /// 列表按它倒序，有新消息时刷新
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
    /// `ChatRole` 的 rawValue
    var roleRaw: String
    /// 正文 Markdown
    var content: String
    /// 思考过程，仅推理模型有
    var reasoning: String?
    /// `MessageStatus` 的 rawValue
    var statusRaw: String
    /// 失败/中断时展示给用户的文案
    var errorMessage: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var createdAt: Double
    /// 当前占有这条消息的生成任务 id；重新生成会换新 id，旧任务的写入随之失效
    var generationID: String? = nil
    /// 快照序号，单调递增；落库时只接受比库里更新的快照
    var snapshotSequence: Int64 = 0
    /// 最近一次快照落库时间
    var checkpointAt: Double? = nil
    /// 结束原因（停止原因、用户停止、进程重启等），用于诊断
    var endReason: String? = nil

    var role: ChatRole { ChatRole(rawValue: roleRaw) ?? .user }
    var status: MessageStatus { MessageStatus(rawValue: statusRaw) ?? .completed }
}
