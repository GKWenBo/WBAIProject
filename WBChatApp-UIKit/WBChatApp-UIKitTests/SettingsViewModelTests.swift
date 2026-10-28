import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 测试专用的内存 Keychain 实现，与生产 Keychain 槽位完全隔离，
/// 避免测试写入的假数据碰到真实用户的 Key。
final class InMemoryKeychainStore: KeychainStoring {
    private var storage: [String: String] = [:]

    func save(_ value: String, for key: String) throws { storage[key] = value }
    func read(_ key: String) -> String? { storage[key] }
    func delete(_ key: String) throws { storage.removeValue(forKey: key) }
}

/// 可编排的假模型目录：按 Key 决定远端返回或失败，不触网也不写 UserDefaults。
final class FakeModelCatalog: ModelCatalogProviding, @unchecked Sendable {
    var cached: [ProviderKind: [ModelInfo]] = [:]
    var handler: @Sendable (ProviderConfig) async throws -> RemoteModelCatalog = { _ in
        throw ChatError.network(code: -1)
    }
    private(set) var fetchCount = 0

    func cachedModels(for provider: ProviderKind) -> [ModelInfo] {
        cached[provider] ?? ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: provider))
    }

    func fetchLatestModels(config: ProviderConfig) async throws -> RemoteModelCatalog {
        fetchCount += 1
        return try await handler(config)
    }
}

@Suite("设置 ViewModel", .serialized)
@MainActor
struct SettingsViewModelTests {

    private func make(catalog: FakeModelCatalog = FakeModelCatalog(),
                      savedAPIKey: String? = nil) -> (SettingsViewModel, AppSettings) {
        let suiteName = "settings.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults, keychain: InMemoryKeychainStore())
        if let savedAPIKey { try? settings.setAPIKey(savedAPIKey) }
        return (SettingsViewModel(settings: settings, catalog: catalog), settings)
    }

    private func waitUntil(timeoutSeconds: Double = 2, condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func ids(_ models: [ModelInfo]) -> [String] { models.map(\.id) }

    @Test("默认服务商是 DeepSeek")
    func defaultProvider() {
        let (viewModel, _) = make()
        #expect(viewModel.provider == .deepSeek)
    }

    @Test("切换服务商时模型与 baseURL 跟着换成该家默认值")
    func switchingProviderResetsModelAndBaseURL() {
        let (viewModel, _) = make()
        viewModel.provider = .anthropic
        #expect(viewModel.model == BundledModelCatalog.defaultModel(for: .anthropic))
        #expect(viewModel.baseURLText == "https://api.anthropic.com")
    }

    @Test("可选模型列表随服务商变化，无 Key 时展示本地兜底且不超过 3 个")
    func availableModelsFollowProvider() {
        let (viewModel, _) = make()
        viewModel.provider = .openAI
        #expect(ids(viewModel.availableModels).contains("gpt-6-astra"))
        #expect(viewModel.availableModels.count <= 3)
        viewModel.provider = .anthropic
        #expect(ids(viewModel.availableModels).contains("claude-sonnet-5-5"))
        #expect(viewModel.availableModels.count <= 3)
    }

    @Test("没有 Key 时不请求远端，保持本地兜底列表")
    func refreshWithoutKeyKeepsBundled() async {
        let catalog = FakeModelCatalog()
        let (viewModel, _) = make(catalog: catalog)
        await viewModel.refreshModels()
        #expect(catalog.fetchCount == 0)
        #expect(viewModel.availableModels == ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: .deepSeek)))
        #expect(viewModel.isLoadingModels == false)
    }

    @Test("远端拉取成功后覆盖本地兜底列表")
    func remoteResultOverridesBundled() async {
        let catalog = FakeModelCatalog()
        let latest = [ModelInfo(id: "deepseek-flash", isSubscription: true), ModelInfo(id: "deepseek-v5")]
        catalog.handler = { _ in RemoteModelCatalog(recommended: latest, allIDs: ["deepseek-flash", "deepseek-v5"]) }
        let (viewModel, _) = make(catalog: catalog, savedAPIKey: "sk-test")
        await viewModel.refreshModels()
        #expect(viewModel.availableModels == latest)
        #expect(viewModel.model == "deepseek-flash")
    }

    @Test("远端失败时保留兜底列表，不改用户已选模型")
    func remoteFailureKeepsBundledAndSelection() async {
        let catalog = FakeModelCatalog()
        let (viewModel, _) = make(catalog: catalog, savedAPIKey: "sk-test")
        viewModel.model = "deepseek-v4-pro"
        await viewModel.refreshModels()
        #expect(catalog.fetchCount >= 1)
        #expect(viewModel.availableModels == ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: .deepSeek)))
        #expect(viewModel.model == "deepseek-v4-pro")
    }

    @Test("当前选中模型已从远端下线时自动切到推荐第一个")
    func retiredModelSwitchesToFirstRecommended() async {
        let catalog = FakeModelCatalog()
        // 上次远端结果里还有 deepseek-old，这次远端已没有
        catalog.cached[.deepSeek] = [ModelInfo(id: "deepseek-old"), ModelInfo(id: "deepseek-flash")]
        let latest = [ModelInfo(id: "deepseek-flash", isSubscription: true)]
        catalog.handler = { _ in RemoteModelCatalog(recommended: latest, allIDs: ["deepseek-flash"]) }
        let (_, settings) = make(catalog: catalog, savedAPIKey: "sk-test")
        settings.model = "deepseek-old"
        let viewModel = SettingsViewModel(settings: settings, catalog: catalog)
        #expect(viewModel.model == "deepseek-old")
        await viewModel.refreshModels()
        #expect(viewModel.model == "deepseek-flash")
    }

    @Test("启动时已存的模型既不在缓存也不在本地清单，直接换成推荐第一个")
    func unknownStoredModelReplacedOnInit() {
        let (_, settings) = make()
        settings.model = "deepseek-chat"   // 模拟升级前存下的已下线模型
        let viewModel = SettingsViewModel(settings: settings, catalog: FakeModelCatalog())
        #expect(viewModel.model == "deepseek-flash")
    }

    @Test("晚到的旧刷新结果被丢弃，不覆盖新结果")
    func staleRefreshResultIsDropped() async {
        let catalog = FakeModelCatalog()
        let old = [ModelInfo(id: "old-model")]
        let new = [ModelInfo(id: "new-model")]
        catalog.handler = { config in
            if config.apiKey == "sk-slow" {
                try? await Task.sleep(nanoseconds: 300_000_000)
                return RemoteModelCatalog(recommended: old, allIDs: ["old-model"])
            }
            return RemoteModelCatalog(recommended: new, allIDs: ["new-model"])
        }
        let (viewModel, _) = make(catalog: catalog, savedAPIKey: "sk-slow")
        let slow = Task { await viewModel.refreshModels() }
        await waitUntil { catalog.fetchCount == 1 }

        viewModel.apiKey = "sk-fast"   // 触发新一轮刷新
        await waitUntil { viewModel.availableModels == new }
        await slow.value

        #expect(viewModel.availableModels == new)
        #expect(viewModel.model == "new-model")
    }

    @Test("save 后设置落盘")
    func savePersists() {
        let (viewModel, settings) = make()
        viewModel.provider = .openAI
        viewModel.model = "gpt-6.1-sol"
        viewModel.systemPrompt = "简短作答"
        viewModel.save()

        #expect(settings.provider == .openAI)
        #expect(settings.model == "gpt-6.1-sol")
        #expect(settings.systemPrompt == "简短作答")
    }

    @Test("API Key 掩码只露首尾")
    func maskedKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = "sk-1234567890abcdef"
        #expect(viewModel.maskedAPIKey.hasPrefix("sk-1"))
        #expect(viewModel.maskedAPIKey.hasSuffix("cdef"))
        #expect(viewModel.maskedAPIKey.contains("****"))
    }

    @Test("短 Key 全部掩码，不泄露内容")
    func shortKeyFullyMasked() {
        let (viewModel, _) = make()
        viewModel.apiKey = "abc"
        #expect(!viewModel.maskedAPIKey.contains("abc"))
    }

    @Test("空 Key 显示未配置")
    func emptyKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = ""
        #expect(viewModel.maskedAPIKey == "未配置")
    }

    @Test("没有 Key 时测试连接直接返回缺 Key 错误")
    func testConnectionWithoutKey() async {
        let (viewModel, _) = make()
        viewModel.apiKey = ""
        let result = await viewModel.testConnection()
        guard case .failure(let error) = result else {
            Issue.record("应当失败")
            return
        }
        #expect(error == .missingAPIKey)
    }

    @Test("切换服务商只触发一次 onChange，不会因级联赋值(model/baseURLText/apiKey)多次刷新")
    func providerSwitchFiresOnChangeExactlyOnce() {
        let (viewModel, _) = make()
        var count = 0
        viewModel.onChange = { count += 1 }
        viewModel.provider = .openAI
        #expect(count == 1)
    }

    @Test("修改单个字段各自触发一次 onChange")
    func fieldChangeFiresOnChangeOnce() {
        let (viewModel, _) = make()
        viewModel.provider = .openAI   // 先切换，排除级联赋值的干扰
        var count = 0
        viewModel.onChange = { count += 1 }
        viewModel.model = "gpt-6.1-sol"   // 与 openAI 的默认模型 "gpt-6-astra" 不同，确保确实发生了变化
        #expect(count == 1)
    }

    @Test("API Key 输入框留空点确定，不修改已保存的真实 Key")
    func emptyAPIKeyInputDoesNotClearExistingKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = "sk-real-secret"
        viewModel.updateAPIKeyIfProvided("")
        #expect(viewModel.apiKey == "sk-real-secret")
    }

    @Test("API Key 输入框有内容时正常更新")
    func nonEmptyAPIKeyInputUpdatesKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = "sk-old"
        viewModel.updateAPIKeyIfProvided("sk-new")
        #expect(viewModel.apiKey == "sk-new")
    }

    @Test("显式清除 Key 会真正清空，与「留空不修改」区分开")
    func explicitClearRemovesKey() {
        let (viewModel, _) = make()
        viewModel.apiKey = "sk-real-secret"
        viewModel.clearAPIKey()
        #expect(viewModel.apiKey == "")
    }

    @Test("baseURL 格式非法时 save 返回 false，且旧的 baseURL 原样保留")
    func saveFailsAndKeepsOldBaseURLWhenInvalid() {
        let (viewModel, settings) = make()
        let original = settings.baseURL
        viewModel.baseURLText = ""
        let success = viewModel.save()
        #expect(success == false)
        #expect(settings.baseURL == original)
    }

    @Test("baseURL 合法时 save 返回 true 并落盘")
    func saveSucceedsForValidBaseURL() {
        let (viewModel, settings) = make()
        viewModel.baseURLText = "https://example.com/v1"
        let success = viewModel.save()
        #expect(success == true)
        #expect(settings.baseURL.absoluteString == "https://example.com/v1")
    }

    @Test("切换服务商后，apiKey 反映的是目标服务商在 Keychain 里已保存的 Key，而非当前持久化 provider 的")
    func switchingProviderReadsTargetProviderKeyViaAppSettings() {
        let (viewModel, _) = make()
        // 直接通过 AppSettings 封装为 openAI 存一个 Key，模拟“之前配置过”
        viewModel.provider = .openAI
        viewModel.apiKey = "sk-openai-key"
        viewModel.save()

        // 切到另一家再切回来，应该能读到刚才存的 Key（走 AppSettings，而不是绕开它直连 KeychainStore）
        viewModel.provider = .anthropic
        #expect(viewModel.apiKey == "")
        viewModel.provider = .openAI
        #expect(viewModel.apiKey == "sk-openai-key")
    }
}
