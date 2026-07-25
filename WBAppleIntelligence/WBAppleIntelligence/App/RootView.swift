import FoundationModels
import SwiftUI

/// 能力目录首页。
///
/// 直接在 body 里读 `SystemLanguageModel.default.availability`：该类型遵循 `Observable`，
/// 用户在系统设置中开启 Apple Intelligence 后，这里会自动刷新，无需重启 App，也无需自己监听通知。
struct RootView: View {
    private let model = SystemLanguageModel.default

    var body: some View {
        NavigationStack {
            List {
                Section {
                    AvailabilityBanner(availability: ModelAvailability(model.availability))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Section("能力") {
                    ForEach(DemoRoute.allCases) { route in
                        NavigationLink(value: route) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title)
                                    Text(route.scenario)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            } icon: {
                                Image(systemName: route.systemImage)
                            }
                        }
                    }
                }
            }
            .navigationTitle("端侧 AI 能力")
            .navigationDestination(for: DemoRoute.self) { destination(for: $0) }
        }
    }

    @ViewBuilder
    private func destination(for route: DemoRoute) -> some View {
        switch route {
        case .availability: AvailabilityDemoView()
        case .streamingChat: ChatDemoView()
        case .ticketExtraction: TicketExtractionDemoView()
        case .toolCalling: ToolCallingDemoView()
        }
    }
}

#Preview {
    RootView()
}
