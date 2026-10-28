import Foundation

/// 非敏感配置走 UserDefaults，API Key 走 Keychain。
final class AppSettings {

    private enum Key {
        static let provider = "settings.provider"
        static let model = "settings.model"
        static let baseURL = "settings.baseURL"
        static let systemPrompt = "settings.systemPrompt"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStoring

    init(defaults: UserDefaults = .standard, keychain: KeychainStoring = KeychainStore.shared) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// 当前服务商，未设置时默认 DeepSeek
    var provider: ProviderKind {
        get { ProviderKind(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .deepSeek }
        set { defaults.set(newValue.rawValue, forKey: Key.provider) }
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? provider.defaultModel }
        set { defaults.set(newValue, forKey: Key.model) }
    }

    /// 自定义接口地址，未设置时取服务商默认地址
    var baseURL: URL {
        get {
            guard let raw = defaults.string(forKey: Key.baseURL), let url = URL(string: raw) else {
                return provider.defaultBaseURL
            }
            return url
        }
        set { defaults.set(newValue.absoluteString, forKey: Key.baseURL) }
    }

    var systemPrompt: String {
        get { defaults.string(forKey: Key.systemPrompt) ?? "你是一个乐于助人的 AI 助手，回答简洁准确。" }
        set { defaults.set(newValue, forKey: Key.systemPrompt) }
    }

    /// 当前服务商的 Key
    var apiKey: String {
        get { apiKey(for: provider) }
    }

    /// 读取指定服务商的 Key，供切换服务商时预览目标服务商已保存的 Key，
    /// 不依赖当前已持久化的 provider。
    func apiKey(for provider: ProviderKind) -> String {
        keychain.read(KeychainStore.key(for: provider)) ?? ""
    }

    /// 保存当前服务商的 Key，传空串即删除
    func setAPIKey(_ key: String) throws {
        if key.isEmpty {
            try keychain.delete(KeychainStore.key(for: provider))
        } else {
            try keychain.save(key, for: KeychainStore.key(for: provider))
        }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    /// 各家 Key 都由可打印 ASCII 组成（字母、数字、- _ . 等），不含空白
    static func isPlausibleAPIKey(_ key: String) -> Bool {
        !key.isEmpty && key.unicodeScalars.allSatisfy { (0x21...0x7E).contains($0.value) }
    }

    #if DEBUG
    /// 调试用的启动环境变量，在 Xcode「Edit Scheme → Run → Arguments」里配置
    enum DebugEnvironment {
        /// 服务商：deepSeek / openAI / anthropic，可选
        static let provider = "WBCHAT_PROVIDER"
        /// 写入该服务商 Keychain 槽位的 Key
        static let apiKey = "WBCHAT_API_KEY"
    }

    /// 用启动环境变量覆盖服务商与 Key，省去在模拟器里粘贴。
    /// Key 仍经 Keychain 保存，不落 UserDefaults；返回是否写入了 Key。
    @discardableResult
    func applyDebugEnvironment(_ environment: [String: String]) -> Bool {
        if let raw = environment[DebugEnvironment.provider], let kind = ProviderKind(rawValue: raw),
           kind != provider {
            provider = kind
            // 换服务商时旧的模型与地址属于上一家，清掉回落到新服务商的默认值
            defaults.removeObject(forKey: Key.model)
            defaults.removeObject(forKey: Key.baseURL)
        }

        let key = (environment[DebugEnvironment.apiKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        guard Self.isPlausibleAPIKey(key) else {
            print("[AppSettings] \(DebugEnvironment.apiKey) 含空白或非 ASCII 字符，已忽略")
            return false
        }
        guard key != apiKey else { return false }
        do {
            try setAPIKey(key)
            return true
        } catch {
            print("[AppSettings] \(DebugEnvironment.apiKey) 写入 Keychain 失败")
            return false
        }
    }
    #endif

    /// 组装发起请求用的配置快照
    var currentConfig: ProviderConfig {
        ProviderConfig(kind: provider, baseURL: baseURL, apiKey: apiKey, model: model)
    }
}
