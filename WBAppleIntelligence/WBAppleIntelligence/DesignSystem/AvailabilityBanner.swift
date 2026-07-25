import SwiftUI

/// 端侧模型可用性横幅。
///
/// 不可用时不隐藏功能入口，而是把原因和下一步操作讲清楚——
/// 企业 App 里「按钮点了没反应」产生的工单，比「明确告诉你为什么不能用」多得多。
struct AvailabilityBanner: View {
    let availability: ModelAvailability

    var body: some View {
        switch availability {
        case .available:
            Label("端侧模型已就绪，推理全程在本机完成", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label(reason.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(reason.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason.recovery)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        AvailabilityBanner(availability: .available)
        AvailabilityBanner(availability: .unavailable(.deviceNotEligible))
    }
    .padding()
}
