import SwiftUI

/// Demo 页面的统一骨架：顶部场景卡片 + 自定义内容区。
///
/// `isScrollable` 是必要的开关：抽取和工具调用这类页面内容会长过一屏，需要滚动；
/// 而对话页自己有一个撑满高度的消息列表，外层再套 ScrollView 会导致列表塌陷成零高度。
struct DemoScaffold<Content: View>: View {
    let route: DemoRoute
    var isScrollable: Bool = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        Group {
            if isScrollable {
                ScrollView { stack.padding() }
            } else {
                stack.padding()
            }
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var stack: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScenarioCard(route: route)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
