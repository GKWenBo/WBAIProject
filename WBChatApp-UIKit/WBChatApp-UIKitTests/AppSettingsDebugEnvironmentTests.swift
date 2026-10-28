import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("调试环境变量注入")
struct AppSettingsDebugEnvironmentTests {

    private func make() -> AppSettings {
        let defaults = UserDefaults(suiteName: "settings.debugenv.\(UUID().uuidString)")!
        return AppSettings(defaults: defaults, keychain: InMemoryKeychainStore())
    }

    @Test("WBCHAT_API_KEY 写入当前服务商的 Keychain 槽位，首尾空白被去掉")
    func apiKeyIsWrittenToKeychain() {
        let settings = make()
        let written = settings.applyDebugEnvironment(["WBCHAT_API_KEY": " sk-debug-123\n"])
        #expect(written)
        #expect(settings.apiKey == "sk-debug-123")
    }

    @Test("WBCHAT_PROVIDER 切换服务商，并把 Key 写到新服务商名下，模型与地址回落默认")
    func providerOverrideSwitchesProvider() {
        let settings = make()
        settings.model = "deepseek-v4-pro"
        settings.baseURL = URL(string: "https://example.com")!
        settings.applyDebugEnvironment(["WBCHAT_PROVIDER": "anthropic", "WBCHAT_API_KEY": "sk-ant-debug"])

        #expect(settings.provider == .anthropic)
        #expect(settings.apiKey(for: .anthropic) == "sk-ant-debug")
        #expect(settings.apiKey(for: .deepSeek) == "")
        #expect(settings.model == ProviderKind.anthropic.defaultModel)
        #expect(settings.baseURL == ProviderKind.anthropic.defaultBaseURL)
    }

    @Test("Key 含空白或非 ASCII 时忽略，不覆盖已有 Key")
    func invalidKeyIsIgnored() throws {
        let settings = make()
        try settings.setAPIKey("sk-existing")
        let written = settings.applyDebugEnvironment(["WBCHAT_API_KEY": "func greet() {  return \"你好\" }"])
        #expect(!written)
        #expect(settings.apiKey == "sk-existing")
    }

    @Test("未配置环境变量时不做任何修改")
    func emptyEnvironmentIsNoOp() {
        let settings = make()
        #expect(!settings.applyDebugEnvironment([:]))
        #expect(settings.provider == .deepSeek)
        #expect(settings.apiKey == "")
    }

    @Test("未知的服务商取值被忽略")
    func unknownProviderIsIgnored() {
        let settings = make()
        settings.applyDebugEnvironment(["WBCHAT_PROVIDER": "gemini"])
        #expect(settings.provider == .deepSeek)
    }
}
