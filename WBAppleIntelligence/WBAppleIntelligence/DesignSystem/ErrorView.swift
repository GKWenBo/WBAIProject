import SwiftUI

/// 统一错误展示。始终同时呈现「发生了什么」与「该怎么办」两段信息。
struct ErrorView: View {
    let error: AIKitError
    var retry: (() -> Void)?

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
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.red.opacity(0.1), in: .rect(cornerRadius: 10))
    }
}

#Preview {
    ErrorView(error: .contextWindowExceeded, retry: {})
        .padding()
}
