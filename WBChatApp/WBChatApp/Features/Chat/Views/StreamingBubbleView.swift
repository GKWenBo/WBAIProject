//
//  StreamingBubbleView.swift
//  WBChatApp
//

import MarkdownUI
import SwiftUI

/// 正在流式生成的气泡：思考过程实时展开，正文末尾带光标
struct StreamingBubbleView: View {

    let viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.streamingReasoning.isEmpty {
                ThinkingSectionView(reasoning: viewModel.streamingReasoning, isInitiallyExpanded: true)
            }

            if viewModel.streamingContent.isEmpty && viewModel.streamingReasoning.isEmpty {
                thinkingIndicator
            } else if !viewModel.streamingContent.isEmpty {
                Markdown(viewModel.streamingContent + " ▍")
                    .markdownTheme(.wbChat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("正在思考…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
