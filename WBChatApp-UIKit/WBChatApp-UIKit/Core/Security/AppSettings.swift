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

    var provider: ProviderKind {
        get { ProviderKind(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .deepSeek }
        set { defaults.set(newValue.rawValue, forKey: Key.provider) }
    }

    var model: String {
        get { defaults.string(forKey: Key.model) ?? provider.defaultModel }
        set { defaults.set(newValue, forKey: Key.model) }
    }

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

    var apiKey: String {
        get { apiKey(for: provider) }
    }

    /// 读取指定服务商的 Key，供切换服务商时预览目标服务商已保存的 Key，
    /// 不依赖当前已持久化的 provider。
    func apiKey(for provider: ProviderKind) -> String {
        keychain.read(KeychainStore.key(for: provider)) ?? ""
    }

    func setAPIKey(_ key: String) throws {
        if key.isEmpty {
            try keychain.delete(KeychainStore.key(for: provider))
        } else {
            try keychain.save(key, for: KeychainStore.key(for: provider))
        }
    }

    var hasAPIKey: Bool { !apiKey.isEmpty }

    var currentConfig: ProviderConfig {
        ProviderConfig(kind: provider, baseURL: baseURL, apiKey: apiKey, model: model)
    }
}
