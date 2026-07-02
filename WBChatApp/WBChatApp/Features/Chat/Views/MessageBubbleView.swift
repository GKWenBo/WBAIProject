//
//  MessageBubbleView.swift
//  WBChatApp
//

import MarkdownUI
import SwiftUI

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
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !message.currentReasoning.isEmpty {
                ThinkingSectionView(reasoning: message.currentReasoning, isInitiallyExpanded: false)
            }

            Markdown(message.currentContent)
                .markdownTheme(.wbChat)
                .textSelection(.enabled)

            actionBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
