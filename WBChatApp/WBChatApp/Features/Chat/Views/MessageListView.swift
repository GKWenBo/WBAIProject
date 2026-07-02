//
//  MessageListView.swift
//  WBChatApp
//

import SwiftUI

/// 消息列表：懒加载 + 流式期间自动滚动到底部
struct MessageListView: View {

    let conversation: Conversation
    @Bindable var viewModel: ChatViewModel

    private static let bottomAnchorID = "bottom-anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(conversation.sortedMessages) { message in
                        MessageBubbleView(
                            message: message,
                            isLastAssistantMessage: message.id == lastAssistantMessageID,
                            viewModel: viewModel
                        )
                        .id(message.id)
                    }

                    if viewModel.isStreaming {
                        StreamingBubbleView(viewModel: viewModel)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamingContent) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: viewModel.streamingReasoning) {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
            .onChange(of: conversation.messages.count) {
                withAnimation {
                    proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
            }
        }
    }

    private var lastAssistantMessageID: UUID? {
        conversation.sortedMessages.last { $0.role == .assistant }?.id
    }
}
