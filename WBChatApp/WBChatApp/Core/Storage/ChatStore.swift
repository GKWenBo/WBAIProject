//
//  ChatStore.swift
//  WBChatApp
//

import Foundation
import SwiftData

/// 仓储层：集中会话/消息的增删改，把 SwiftData 细节与 ViewModel 隔离
struct ChatStore {

    let context: ModelContext

    @discardableResult
    func createConversation() -> Conversation {
        let conversation = Conversation()
        context.insert(conversation)
        return conversation
    }

    func appendMessage(_ message: Message, to conversation: Conversation) {
        context.insert(message)
        message.conversation = conversation
        conversation.updatedAt = .now
    }

    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        conversation.title = trimmed
        save()
    }

    func delete(_ conversation: Conversation) {
        context.delete(conversation)
        save()
    }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    /// 根据首条用户消息生成默认标题
    nonisolated static func defaultTitle(from text: String) -> String {
        let condensed = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return condensed.isEmpty ? "新对话" : String(condensed.prefix(16))
    }
}
