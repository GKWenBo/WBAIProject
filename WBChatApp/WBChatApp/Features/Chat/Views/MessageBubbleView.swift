//
//  MessageBubbleView.swift
//  WBChatApp
//

import MarkdownUI
import SwiftUI

/// 已解析 Markdown 的缓存：List 复用会回收离屏行，滚回历史时行内容重建，
/// 若不缓存，同一条消息每次重新入屏都要重新解析一遍 Markdown（长回答明显卡顿）。
/// 键为「消息 id + 版本号」，重新生成产生新版本后自然换键，无失效问题
private let markdownCache: NSCache<NSString, ParsedMarkdown> = {
    let cache = NSCache<NSString, ParsedMarkdown>()
    cache.countLimit = 200
    return cache
}()

/// NSCache 只能存 class，包一层装 `MarkdownContent` 值类型
private final class ParsedMarkdown {
    let content: MarkdownContent
    init(_ content: MarkdownContent) { self.content = content }
}

/// 单条消息气泡：用户消息右对齐纯文本，AI 消息左对齐 Markdown + 操作栏
struct MessageBubbleView: View {

    let message: Message
    let isLastAssistantMessage: Bool
    let viewModel: ChatViewModel

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.currentContent)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
                // UI 测试按此定位用户气泡：会话标题取自首条消息，按文本全局查询会命中标题产生歧义
                .accessibilityIdentifier("chat.message.user")
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.currentReasoning.isEmpty {
                ThinkingSectionView(reasoning: message.currentReasoning, isInitiallyExpanded: false)
            }

            Markdown(parsedContent)
                .markdownTheme(.wbChat)
                .textSelection(.enabled)

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 当前版本正文的解析结果：优先取缓存，未命中才解析并回填
    private var parsedContent: MarkdownContent {
        let key = "\(message.id)-\(message.currentVersionIndex)" as NSString
        if let cached = markdownCache.object(forKey: key) {
            return cached.content
        }
        let parsed = MarkdownContent(message.currentContent)
        markdownCache.setObject(ParsedMarkdown(parsed), forKey: key)
        return parsed
    }

    private var actionBar: some View {
        HStack(spacing: 18) {
            if message.versionCount > 1 {
                versionPager
            }

            Button {
                UIPasteboard.general.string = message.currentContent
            } label: {
                Image(systemName: "doc.on.doc")
            }

            Button {
                message.feedback = message.feedback == 1 ? 0 : 1
            } label: {
                Image(systemName: message.feedback == 1 ? "hand.thumbsup.fill" : "hand.thumbsup")
            }

            Button {
                message.feedback = message.feedback == -1 ? 0 : -1
            } label: {
                Image(systemName: message.feedback == -1 ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }

            if isLastAssistantMessage {
                Button {
                    viewModel.regenerate(message)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isStreaming)
            }

            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
    }

    private var versionPager: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.switchVersion(of: message, delta: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(message.currentVersionIndex == 0)

            Text("\(message.currentVersionIndex + 1)/\(message.versionCount)")
                .font(.footnote.monospacedDigit())

            Button {
                viewModel.switchVersion(of: message, delta: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(message.currentVersionIndex == message.versionCount - 1)
        }
    }
}
