import SwiftUI

/// 每个 Demo 顶部的说明卡片：这个能力对应什么企业场景、相比传统方案价值在哪、用到哪些框架。
///
/// 单独抽出来是因为「场景与价值」是这个示例工程的主线，不能散落在各页面里各写一遍。
struct ScenarioCard: View {
    let route: DemoRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(route.frameworks, systemImage: "cube.transparent")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            row(title: "场景", text: route.scenario)
            row(title: "价值", text: route.value)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
    }

    private func row(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    ScenarioCard(route: .streamingChat)
        .padding()
}
