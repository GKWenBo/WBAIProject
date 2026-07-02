//
//  ConversationListViewModel.swift
//  WBChatApp
//

import Foundation
import Observation

/// 会话列表的一个时间分组
struct ConversationSection: Identifiable {
    let title: String
    var conversations: [Conversation]

    var id: String { title }
}

/// 会话列表逻辑：搜索过滤 + 时间分组（纯函数，便于测试）
@Observable
final class ConversationListViewModel {

    var searchText = ""

    /// 过滤 + 分组（今天/昨天/年月）；入参需已按 updatedAt 倒序
    func sections(from conversations: [Conversation]) -> [ConversationSection] {
        var sections: [ConversationSection] = []
        for conversation in filter(conversations) {
            let title = conversation.updatedAt.conversationSectionTitle
            if let lastIndex = sections.indices.last, sections[lastIndex].title == title {
                sections[lastIndex].conversations.append(conversation)
            } else {
                sections.append(ConversationSection(title: title, conversations: [conversation]))
            }
        }
        return sections
    }

    /// 搜索匹配会话标题或任意消息内容
    ///
    /// 演示规模用内存过滤足够；数据量大时应换成 SwiftData 谓词或 FTS。
    func filter(_ conversations: [Conversation]) -> [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.title.localizedStandardContains(query)
                || conversation.messages.contains { message in
                    message.contents.contains { $0.localizedStandardContains(query) }
                }
        }
    }
}
