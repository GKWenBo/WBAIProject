//
//  MarkdownTheme+WBChat.swift
//  WBChatApp
//

import MarkdownUI
import SwiftUI

extension Theme {

    /// App 统一的 Markdown 主题：基于 basic，代码块自定义为带语言标签和复制按钮的卡片
    static let wbChat = Theme.basic
        .codeBlock { configuration in
            CodeBlockView(configuration: configuration)
        }

}

/// 代码块卡片：语言标签 + 复制按钮 + 自动换行的等宽代码
private struct CodeBlockView: View {

    let configuration: CodeBlockConfiguration

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(configuration.language ?? "code")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                copyButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            configuration.label
                .relativeLineSpacing(.em(0.25))
                .markdownTextStyle {
                    FontFamilyVariant(.monospaced)
                    FontSize(.em(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .markdownMargin(top: .em(0.8), bottom: .em(0.8))
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = configuration.content
            didCopy = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        } label: {
            Label(didCopy ? "已复制" : "复制", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                .font(.caption)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
