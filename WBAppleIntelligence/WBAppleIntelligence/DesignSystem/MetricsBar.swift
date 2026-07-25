import SwiftUI

/// 生成指标展示条。没有任何指标时整体隐藏，避免首次进入页面显示一排「--」。
struct MetricsBar: View {
    let metrics: GenerationMetrics

    var body: some View {
        if hasAnyValue {
            HStack(spacing: 14) {
                if let latency = metrics.firstTokenLatency {
                    item("首字", String(format: "%.2f s", latency))
                }
                if let total = metrics.totalDuration {
                    item("总耗时", String(format: "%.2f s", total))
                }
                if let speed = metrics.tokensPerSecond {
                    item("速率", String(format: "%.0f tok/s", speed))
                }
                if let prompt = metrics.promptTokenCount {
                    item("输入", "\(prompt) tok")
                }
                if let response = metrics.responseTokenCount {
                    item("输出", "\(response) tok")
                }
            }
            .font(.caption2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasAnyValue: Bool {
        metrics != .empty
    }

    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.secondary)
            Text(value).monospacedDigit().foregroundStyle(.primary)
        }
    }
}

#Preview {
    MetricsBar(metrics: GenerationMetrics(
        firstTokenLatency: 0.32,
        totalDuration: 4.1,
        promptTokenCount: 86,
        responseTokenCount: 124
    ))
    .padding()
}
