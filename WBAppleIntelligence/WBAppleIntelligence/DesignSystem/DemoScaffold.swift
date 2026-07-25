import FoundationModels
import SwiftUI

/// Demo 页面的统一骨架：顶部场景卡片 + 可用性横幅 + 自定义内容区。
///
/// 可用性探测放在这一层，是因为四个 Demo 页开头那段「读 `SystemLanguageModel.default.availability`
/// 再挂一条横幅」的代码原本一字不差地重复了四遍。骨架读一次，再把结果交给内容闭包，
/// 三个需要用它去 `.disabled(...)` 的页面照样拿得到，不必各自再读一遍模型。
///
/// `isScrollable` 是必要的开关：抽取和工具调用这类页面内容会长过一屏，需要滚动；
/// 而对话页自己有一个撑满高度的消息列表，外层再套 ScrollView 会导致列表塌陷成零高度。
struct DemoScaffold<Content: View>: View {
    let route: DemoRoute
    var isScrollable: Bool = true
    @ViewBuilder var content: (ModelAvailability) -> Content

    private let model = SystemLanguageModel.default

    var body: some View {
        // 这行读取必须留在 body 的求值过程里：`SystemLanguageModel` 遵循 `Observable`，
        // 只有在 body 中读 `availability`，SwiftUI 才会追踪它，用户去系统设置里开关
        // Apple Intelligence 之后界面才会自动刷新。挪进 init 缓存成存储属性就只会算一次，
        // 自动刷新随之失效（详见 Docs/01-可用性探测与降级.md 第 4 节）。
        let availability = ModelAvailability(model.availability)

        Group {
            if isScrollable {
                ScrollView { stack(availability).padding() }
            } else {
                stack(availability).padding()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stack(_ availability: ModelAvailability) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScenarioCard(route: route)
            AvailabilityBanner(availability: availability)
            content(availability)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
