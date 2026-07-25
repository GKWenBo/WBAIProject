import FoundationModels
import SwiftUI

/// Demo 1：端侧模型可用性与能力探测。
///
/// 这一页刻意不放任何生成功能——它要回答的是上线前的第一个问题：
/// 「这台设备到底能不能用端侧模型，不能用是因为什么」。
struct AvailabilityDemoView: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        DemoScaffold(route: .availability) {
            let availability = ModelAvailability(model.availability)

            AvailabilityBanner(availability: availability)

            section("模型能力") {
                keyValue("上下文窗口", "\(model.contextSize) token")
                keyValue("支持语言数", "\(model.supportedLanguages.count)")
                keyValue("支持当前地区", model.supportsLocale() ? "是" : "否")
                keyValue("当前地区标识", Locale.current.identifier)
            }

            section("支持的语言") {
                Text(supportedLanguageList)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            section("这一页为什么重要") {
                Text("""
                端侧能力在设备之间的分布是不均匀的：机型、系统版本、区域、语言、\
                用户是否开启、模型是否下载完，任何一环不满足都会让 availability 变成 unavailable。\
                所以「有没有 AI 功能」不能写死在代码里，必须在运行时探测并给出对应的降级路径。

                注意 supportedLanguages 与 availability 是两件事：\
                即使模型可用，用户的语言也可能不在支持列表里，那时调用会抛 unsupportedLanguageOrLocale。
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var supportedLanguageList: String {
        // maximalIdentifier 是非可选的 String，这里用 map 而不是 compactMap，
        // 后者在闭包结果非可选时会触发编译器告警。
        let names = model.supportedLanguages
            .map(\.maximalIdentifier)
            .sorted()
        return names.isEmpty ? "模型不可用时无法读取语言列表。" : names.joined(separator: "、")
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keyValue(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

#Preview {
    NavigationStack {
        AvailabilityDemoView()
    }
}
