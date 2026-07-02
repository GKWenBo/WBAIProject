//
//  Conversation.swift
//  WBChatApp
//

import Foundation
import SwiftData

/// 一次会话，对应抽屉列表中的一行
@Model
final class Conversation {
    var id: UUID
    var title: String
    var createdAt: Date
    /// 最近活跃时间，列表排序与时间分组的依据
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    init(title: String = "新对话", createdAt: Date = .now) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = []
    }

    /// 按发送时间排序后的消息（SwiftData 的关系数组不保证顺序）
    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}
