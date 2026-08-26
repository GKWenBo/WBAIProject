import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("设置 ViewModel", .serialized)
@MainActor
struct SettingsViewModelTests {

    private func make() -> (SettingsViewModel, AppSettings) {
        let suiteName = "settings.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = AppSettings(defaults: defaults)
        return (SettingsViewModel(settings: settings), settings)
    }

    @Test("默认服务商是 DeepSeek")
    func defaultProvider() {
        let (viewModel, _) = make()
        #expect(viewModel.provider == .deepSeek)
    }

    @Test("切换服务商时模型与 baseURL 跟着换成该家默认值")
    func switchingProviderResetsModelAndBaseURL() {
        let (viewModel, _) = make()
        viewModel.provider = .anthropic
        #expect(viewModel.model == "claude-sonnet-5")
        #expect(viewModel.baseURLText == "https://api.anthropic.com")
    }

    @Test("可选模型列表随服务商变化")
    func availableModelsFollowProvider() {
        let (viewModel, _) = make()
        viewModel.provider = .openAI
        #expect(viewModel.availableModels.contains("gpt-4o"))
        viewModel.provider = .anthropic
        #expect(viewModel.availableModels.contains("claude-sonnet-5"))
    }

    @Test("save 后设置落盘")
    func savePersists() {
        let (viewModel, settings) = make()
        viewModel.provider = .openAI
        viewModel.model = "gpt-4o-mini"
        viewModel.systemPrompt = "简短作答"
        viewModel.save()

        #expect(settings.provider == .openAI)
        #expect(settings.model == "gpt-4o-mini")
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

    @Test("修改任一项触发 onChange")
    func onChangeFires() {
        let (viewModel, _) = make()
        var count = 0
        viewModel.onChange = { count += 1 }
        viewModel.provider = .openAI
        viewModel.model = "gpt-4o"
        #expect(count >= 2)
    }
}
