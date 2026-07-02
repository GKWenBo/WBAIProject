//
//  ChatView.swift
//  WBChatApp
//

import SwiftUI

/// 聊天主页面：导航栏 + 消息列表 + 输入栏
struct ChatView: View {

    @Bindable var viewModel: ChatViewModel
    @Environment(AppRouter.self) private var router
    @State private var speechRecognizer = SpeechRecognizer()

    var body: some View {
        VStack(spacing: 0) {
            header

            if let errorMessage = viewModel.errorMessage {
                errorBanner(errorMessage)
            }

            Group {
                if let conversation = viewModel.conversation {
                    MessageListView(conversation: conversation, viewModel: viewModel)
                } else {
                    emptyState
                }
            }
            // 点击或下滑消息区域收起键盘（列表滚动本身已由 scrollDismissesKeyboard 跟手收起）
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.height > 30 {
                        hideKeyboard()
                    }
                }
            )

            InputBarView(viewModel: viewModel, speechRecognizer: speechRecognizer)
        }
        .background(Color(.systemBackground))
        .overlay {
            if speechRecognizer.isRecording {
                RecordingOverlayView(
                    levels: speechRecognizer.levels,
                    transcript: speechRecognizer.transcript
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: speechRecognizer.isRecording)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                router.openDrawer()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .accessibilityIdentifier("chat.menu")

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.conversation?.title ?? "新对话")
                    .font(.headline)
                    .lineLimit(1)
                Text(viewModel.isUsingMockData ? "⚡ 演示模式" : "回答由 AI 生成，仅供参考")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.startNewConversation()
            } label: {
                Image(systemName: "plus.bubble")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("有什么可以帮你的？")
                .font(.title3.weight(.medium))
            if viewModel.isUsingMockData {
                Button("前往设置配置 DeepSeek API Key") {
                    router.isSettingsPresented = true
                }
                .font(.footnote)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
        }
        .font(.footnote)
        .foregroundStyle(.red)
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }
}
