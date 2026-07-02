//
//  ChatViewModel.swift
//  WBChatApp
//

import Foundation
import Observation
import SwiftData

/// 聊天会话核心逻辑：发送、流式接收、重新生成、版本切换、停止
@Observable
final class ChatViewModel {

    // MARK: - UI State

    /// 当前打开的会话；`nil` 表示新对话（发送首条消息时才落库）
    var conversation: Conversation?
    var draft = ""
    var isDeepThinkingEnabled = false
    var isStreaming = false
    /// 正在被「重新生成」的消息 id；`nil` 表示当前是新消息生成而非重新生成。
    /// 用于让 UI 把流式内容原地替换到该条消息，而不是在底部另起气泡。
    private(set) var regeneratingMessageID: UUID?
    /// 正在流式生成的正文/思考过程（结束后落库并清空）
    private(set) var streamingContent = ""
    private(set) var streamingReasoning = ""
    var errorMessage: String?

    var isUsingMockData: Bool {
        !settings.isConfigured
    }

    // MARK: - Dependencies

    private let settings: AppSettings
    private var store: ChatStore?
    private var streamTask: Task<Void, Never>?

    /// 流式 UI 刷新节流间隔：避免每个 token 都触发一次 Markdown 重解析与布局
    private static let flushInterval: TimeInterval = 0.05

    init(settings: AppSettings) {
        self.settings = settings
    }

    /// 注入 ModelContext（来自 SwiftUI 环境，无法在 init 时拿到）
    func configure(context: ModelContext) {
        guard store == nil else { return }
        store = ChatStore(context: context)
    }

    // MARK: - Conversation

    func startNewConversation() {
        stopStreaming()
        conversation = nil
        errorMessage = nil
    }

    func open(_ conversation: Conversation) {
        guard conversation.id != self.conversation?.id else { return }
        stopStreaming()
        self.conversation = conversation
        errorMessage = nil
    }

    // MARK: - Sending

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let store else { return }

        let conversation = self.conversation ?? store.createConversation()
        self.conversation = conversation
        if conversation.messages.isEmpty {
            conversation.title = ChatStore.defaultTitle(from: text)
        }
        store.appendMessage(Message(role: .user, content: text), to: conversation)
        store.save()
        draft = ""

        stream(into: conversation, history: payloads(for: conversation), regenerating: nil)
    }

    /// 重新生成：以该条 assistant 消息之前的上下文重新请求，结果作为新版本追加
    func regenerate(_ message: Message) {
        guard !isStreaming, let conversation, message.role == .assistant else { return }
        let history = payloads(for: conversation, before: message)
        guard !history.isEmpty else { return }
        stream(into: conversation, history: history, regenerating: message)
    }

    func stopStreaming() {
        streamTask?.cancel()
    }

    func switchVersion(of message: Message, delta: Int) {
        let target = message.currentVersionIndex + delta
        guard message.contents.indices.contains(target) else { return }
        message.currentVersionIndex = target
        store?.save()
    }

    // MARK: - Streaming

    private func stream(into conversation: Conversation, history: [ChatMessagePayload], regenerating target: Message?) {
        isStreaming = true
        regeneratingMessageID = target?.id
        streamingContent = ""
        streamingReasoning = ""
        errorMessage = nil

        streamTask = Task { [weak self] in
            guard let self else { return }
            var content = ""
            var reasoning = ""
            var lastFlush = Date.distantPast
            do {
                let config = try self.settings.requestConfig(deepThinking: self.isDeepThinkingEnabled)
                let client = self.makeClient()
                for try await chunk in client.streamChat(messages: history, config: config) {
                    if let delta = chunk.deltaReasoning { reasoning += delta }
                    if let delta = chunk.deltaContent { content += delta }

                    let now = Date()
                    if now.timeIntervalSince(lastFlush) >= Self.flushInterval {
                        lastFlush = now
                        self.streamingContent = content
                        self.streamingReasoning = reasoning
                    }
                }
            } catch is CancellationError {
                // 用户主动停止：保留已生成内容
            } catch let error as URLError where error.code == .cancelled {
                // 同上，URLSession 层的取消
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.finishStreaming(content: content, reasoning: reasoning, conversation: conversation, target: target)
        }
    }

    private func finishStreaming(content: String, reasoning: String, conversation: Conversation, target: Message?) {
        defer {
            isStreaming = false
            regeneratingMessageID = nil
            streamingContent = ""
            streamingReasoning = ""
            streamTask = nil
        }
        guard let store, !content.isEmpty || !reasoning.isEmpty else { return }

        if let target {
            target.appendVersion(content: content, reasoning: reasoning)
            conversation.updatedAt = .now
        } else {
            store.appendMessage(Message(role: .assistant, content: content, reasoning: reasoning), to: conversation)
        }
        store.save()
    }

    /// 把会话消息转为请求负载；`boundary` 之前（不含）的消息用于重新生成
    private func payloads(for conversation: Conversation, before boundary: Message? = nil) -> [ChatMessagePayload] {
        var messages = conversation.sortedMessages
        if let boundary, let index = messages.firstIndex(where: { $0.id == boundary.id }) {
            messages = Array(messages[..<index])
        }
        return messages.map { ChatMessagePayload(role: $0.role.rawValue, content: $0.currentContent) }
    }

    private func makeClient() -> ChatStreaming {
        settings.isConfigured ? DeepSeekClient() : MockChatClient()
    }
}
