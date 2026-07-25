import SwiftUI

/// Demo 4：工具调用接内部系统。
///
/// 界面上把「工具调用轨迹」单独列出来，是因为企业场景里这部分必须可审计——
/// 需要能回答「这个数字是模型编的还是真查出来的」。
struct ToolCallingDemoView: View {
    @State private var viewModel = ToolCallingViewModel()

    var body: some View {
        DemoScaffold(route: .toolCalling) { availability in
            Text("试试这些问题")
                .font(.subheadline.weight(.semibold))
            ForEach(ToolCallingViewModel.samples, id: \.self) { sample in
                Button(sample) { viewModel.input = sample }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isAsking)
            }

            TextField("用自然语言提问", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .disabled(viewModel.isAsking)

            HStack {
                Button("提问") {
                    Task { await viewModel.ask() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!availability.isAvailable || !viewModel.canAsk)

                Button("清空") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isAsking)

                if viewModel.isAsking {
                    ProgressView().padding(.leading, 4)
                }
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            if !viewModel.toolCalls.isEmpty {
                toolTrace
            }

            if !viewModel.answer.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("回答").font(.subheadline.weight(.semibold))
                    Text(viewModel.answer)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MetricsBar(metrics: viewModel.metrics)
        }
    }

    private var toolTrace: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("工具调用轨迹", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.semibold))
            ForEach(viewModel.toolCalls) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.toolName)
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(record.output)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }
}

#Preview {
    NavigationStack {
        ToolCallingDemoView()
    }
}
