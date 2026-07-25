import SwiftUI

/// 统一错误展示。始终同时呈现「发生了什么」与「该怎么办」两段信息。
///
/// 刻意不带「重试」按钮：三个 Demo 的重试入口都是各自页面上原本就有的那个主按钮
///（发送 / 抽取工单 / 提问），错误块里再放一个只会让「该点哪个」变得含糊。
struct ErrorView: View {
    let error: AIKitError

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.errorDescription ?? "出错了", systemImage: "xmark.octagon.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
            if let suggestion = error.recoverySuggestion {
                Text(suggestion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

#Preview {
    ErrorView(error: .contextWindowExceeded)
        .padding()
}
