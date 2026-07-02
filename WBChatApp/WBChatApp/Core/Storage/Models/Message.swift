//
//  Message.swift
//  WBChatApp
//

import Foundation
import SwiftData

enum MessageRole: String {
    case user
    case assistant
}

/// 单条消息
///
/// assistant 消息支持多版本：每次"重新生成"把结果追加到 `contents`，
/// `currentVersionIndex` 指向当前展示的版本（对应 UI 上的 "< i/n >" 切换条）。
/// `reasoningContents` 与 `contents` 按下标一一对应，存深度思考的推理过程，无则为空串。
@Model
final class Message {
    var id: UUID
    var roleRawValue: String
    var contents: [String]
    var reasoningContents: [String]
    var currentVersionIndex: Int
    /// 用户反馈：1 赞，-1 踩，0 无
    var feedback: Int
    var createdAt: Date
    var conversation: Conversation?

    init(role: MessageRole, content: String, reasoning: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.roleRawValue = role.rawValue
        self.contents = [content]
        self.reasoningContents = [reasoning]
        self.currentVersionIndex = 0
        self.feedback = 0
        self.createdAt = createdAt
    }

    var role: MessageRole {
        MessageRole(rawValue: roleRawValue) ?? .user
    }

    var currentContent: String {
        guard contents.indices.contains(currentVersionIndex) else { return contents.last ?? "" }
        return contents[currentVersionIndex]
    }

    var currentReasoning: String {
        guard reasoningContents.indices.contains(currentVersionIndex) else { return "" }
        return reasoningContents[currentVersionIndex]
    }

    var versionCount: Int {
        contents.count
    }

    /// 追加一个新版本并切换到它（重新生成的结果）
    func appendVersion(content: String, reasoning: String) {
        contents.append(content)
        reasoningContents.append(reasoning)
        currentVersionIndex = contents.count - 1
    }
}
