import SwiftUI

/// Demo 3：结构化工单抽取。
///
/// 表格区域始终存在，字段值随生成过程从「等待中」逐个变成实际内容——
/// 这就是 `PartiallyGenerated` 的价值：用户不用盯着转圈等，能看到进度。
struct TicketExtractionDemoView: View {
    @State private var viewModel = TicketExtractionViewModel()

    var body: some View {
        DemoScaffold(route: .ticketExtraction) { availability in
            Text("员工原话")
                .font(.subheadline.weight(.semibold))
            TextField("描述遇到的问题", text: $viewModel.input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .disabled(viewModel.isExtracting)

            HStack {
                Button("抽取工单") {
                    Task { await viewModel.extract() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!availability.isAvailable || !viewModel.canExtract)

                Button("清空") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isExtracting)

                if viewModel.isExtracting {
                    ProgressView().padding(.leading, 4)
                }
            }

            if let error = viewModel.error {
                ErrorView(error: error)
            }

            ticketForm

            MetricsBar(metrics: viewModel.metrics)
        }
    }

    private var ticketForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("结构化结果")
                .font(.subheadline.weight(.semibold))

            field("标题", viewModel.ticket?.title ?? viewModel.partial?.title)
            field("类别", (viewModel.ticket?.category ?? viewModel.partial?.category)?.displayName)
            field("优先级", (viewModel.ticket?.priority ?? viewModel.partial?.priority)?.displayName)
            field("影响人数", (viewModel.ticket?.affectedPeople ?? viewModel.partial?.affectedPeople).map { String($0) })
            field("关键词", (viewModel.ticket?.keywords ?? viewModel.partial?.keywords)?.joined(separator: "、"))
            field("摘要", viewModel.ticket?.summary ?? viewModel.partial?.summary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 12))
    }

    private func field(_ name: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value?.isEmpty == false ? value! : "等待生成…")
                .font(.callout)
                .foregroundStyle(value?.isEmpty == false ? .primary : .tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        TicketExtractionDemoView()
    }
}
