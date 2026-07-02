//
//  InputBarView.swift
//  WBChatApp
//

import SwiftUI

/// 底部输入栏：多行输入 + 深度思考开关 + 按住说话 + 发送/停止
struct InputBarView: View {

    @Bindable var viewModel: ChatViewModel
    @Bindable var speechRecognizer: SpeechRecognizer

    @FocusState private var isInputFocused: Bool
    /// 录音开始时输入框中已有的文本，识别结果追加在其后
    @State private var draftBeforeRecording = ""

    var body: some View {
        VStack(spacing: 10) {
            TextField("发消息或按住说话", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .accessibilityIdentifier("chat.input")

            HStack(spacing: 10) {
                deepThinkingChip
                Spacer()
                microphoneButton
                sendOrStopButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onChange(of: speechRecognizer.transcript) {
            guard !speechRecognizer.transcript.isEmpty else { return }
            viewModel.draft = draftBeforeRecording + speechRecognizer.transcript
        }
        .onChange(of: speechRecognizer.errorMessage) {
            if let message = speechRecognizer.errorMessage {
                viewModel.errorMessage = message
            }
        }
    }

    // MARK: - Subviews

    private var deepThinkingChip: some View {
        Button {
            viewModel.isDeepThinkingEnabled.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "atom")
                Text("深度思考")
            }
            .font(.footnote.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(
                    viewModel.isDeepThinkingEnabled
                        ? Color.accentColor.opacity(0.15)
                        : Color(.systemGray5)
                )
            )
            .foregroundStyle(viewModel.isDeepThinkingEnabled ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var microphoneButton: some View {
        Image(systemName: speechRecognizer.isRecording ? "waveform" : "mic")
            .font(.system(size: 20))
            .foregroundStyle(speechRecognizer.isRecording ? Color.accentColor : .secondary)
            .frame(width: 36, height: 36)
            .contentShape(Circle())
            .gesture(pressAndHoldToRecord)
            .accessibilityLabel("按住说话")

    }

    /// 按住开始录音，松开结束并把识别文字留在输入框
    private var pressAndHoldToRecord: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !speechRecognizer.isRecording else { return }
                isInputFocused = false
                draftBeforeRecording = viewModel.draft
                Task { await speechRecognizer.start() }
            }
            .onEnded { _ in
                speechRecognizer.stop()
            }
    }

    private var sendOrStopButton: some View {
        Button {
            if viewModel.isStreaming {
                viewModel.stopStreaming()
            } else {
                viewModel.send()
            }
        } label: {
            Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(sendButtonEnabled ? Color.accentColor : Color(.systemGray3))
        }
        .buttonStyle(.plain)
        .disabled(!sendButtonEnabled)
        .accessibilityIdentifier("chat.send")
    }

    private var sendButtonEnabled: Bool {
        viewModel.isStreaming
            || !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
