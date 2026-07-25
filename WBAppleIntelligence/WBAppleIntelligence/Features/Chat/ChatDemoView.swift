import SwiftUI

/// Demo 2：流式客服助手。
///
/// 用 `DemoScaffold(isScrollable: false)`：消息列表自己要撑满剩余高度并独立滚动，
/// 外层再套一层 ScrollView 会让列表高度塌陷。
struct ChatDemoView: View {
    @State private var viewModel = ChatViewModel()

    var body: some View {
        DemoScaffold(route: .streamingChat, isScrollable: false) { availability in
            messageList

            if viewModel.didTrimContext {
                Label("早期对话已被裁剪以腾出上下文空间", systemImage: "scissors")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            MetricsBar(metrics: viewModel.metrics)

            temperatureSlider
            inputBar(isEnabled: availability.isAvailable)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("新会话", systemImage: "arrow.counterclockwise") {
                    viewModel.reset()
                }
                .disabled(viewModel.isResponding)
            }
        }
        .task {
            // 用户已经进到对话界面了，这时预热的收益最大、浪费最小。
            viewModel.prewarm()
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List(viewModel.messages) { message in
                MessageRow(message: message)
                    .listRowSeparator(.hidden)
                    .id(message.id)
            }
            .listStyle(.plain)
            .frame(maxHeight: .infinity)
            .onChange(of: viewModel.messages.last?.text) {
                guard let lastID = viewModel.messages.last?.id else { return }
                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
            }
        }
    }

    private var temperatureSlider: some View {
        HStack(spacing: 10) {
            Text("温度 \(viewModel.temperature, format: .number.precision(.fractionLength(1)))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Slider(value: $viewModel.temperature, in: 0...1, step: 0.1)
        }
    }

    private func inputBar(isEnabled: Bool) -> some View {
        HStack(spacing: 8) {
            TextField("描述你遇到的问题", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(!isEnabled)

            Button {
                Task { await viewModel.send() }
            } label: {
                if viewModel.isResponding {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
            }
            .disabled(!isEnabled || !viewModel.canSend)
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "思考中…" : message.text)
                .font(.callout)
                .foregroundStyle(message.text.isEmpty ? .secondary : .primary)
                .padding(10)
                .background(background, in: .rect(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var background: some ShapeStyle {
        message.role == .user ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.5))
    }
}

#Preview {
    NavigationStack {
        ChatDemoView()
    }
}
