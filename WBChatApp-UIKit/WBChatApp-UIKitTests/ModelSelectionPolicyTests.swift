import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("模型选择策略")
struct ModelSelectionPolicyTests {

    private let bundled = [
        ModelInfo(id: "metered-a", isSubscription: false),
        ModelInfo(id: "sub-a", isSubscription: true),
        ModelInfo(id: "sub-b", isSubscription: true),
    ]

    private func remote(_ ids: [String]) -> [ModelInfo] { ids.map { ModelInfo(id: $0) } }

    @Test("订阅模型优先于计量模型，且以本地标注为准")
    func subscriptionFirst() {
        let result = ModelSelectionPolicy.select(remote: remote(["metered-a", "sub-b", "sub-a"]),
                                                 bundled: bundled)
        #expect(result.map(\.id) == ["sub-a", "sub-b", "metered-a"])
        #expect(result[0].isSubscription)
    }

    @Test("最多返回 3 个")
    func capsAtThree() {
        let result = ModelSelectionPolicy.select(remote: remote(["sub-a", "sub-b", "metered-a", "new-x", "new-y"]),
                                                 bundled: bundled)
        #expect(result.count == ModelSelectionPolicy.maxCount)
    }

    @Test("本地清单未收录的新模型按创建时间新→旧补足")
    func unknownModelsSortedByCreatedDesc() {
        let older = ModelInfo(id: "new-old", createdAt: Date(timeIntervalSince1970: 100))
        let newer = ModelInfo(id: "new-new", createdAt: Date(timeIntervalSince1970: 200))
        let result = ModelSelectionPolicy.select(remote: [older, ModelInfo(id: "sub-a"), newer],
                                                 bundled: bundled)
        #expect(result.map(\.id) == ["sub-a", "new-new", "new-old"])
    }

    @Test("远端已下线的清单模型不展示")
    func retiredBundledModelsAreHidden() {
        let result = ModelSelectionPolicy.select(remote: remote(["sub-b"]), bundled: bundled)
        #expect(result.map(\.id) == ["sub-b"])
    }

    @Test("过滤非对话模型与日期快照")
    func filtersNonChatModels() {
        let result = ModelSelectionPolicy.select(
            remote: remote(["text-embedding-3-large", "gpt-realtime-2", "gpt-4o-mini-tts",
                            "gpt-image-2.5-flare", "gpt-6-astra-2026-04-30", "claude-x-20251001", "gpt-6-astra"]),
            bundled: [])
        #expect(result.map(\.id) == ["gpt-6-astra"])
    }

    @Test("远端没有可用模型时回落本地清单，订阅优先")
    func emptyRemoteFallsBackToBundled() {
        let result = ModelSelectionPolicy.select(remote: [], bundled: bundled)
        #expect(result.map(\.id) == ["sub-a", "sub-b", "metered-a"])
    }

    @Test("每家本地清单的默认模型都是订阅模型")
    func bundledDefaultIsSubscription() {
        for provider in ProviderKind.allCases {
            let models = BundledModelCatalog.models(for: provider)
            #expect(!models.isEmpty)
            #expect(models[0].isSubscription)
            #expect(ModelSelectionPolicy.fallback(models)[0].id == provider.defaultModel)
        }
    }
}
