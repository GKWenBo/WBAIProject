import Foundation

@MainActor
final class SettingsViewModel {

    var onChange: (() -> Void)?

    private let settings: AppSettings

    var provider: ProviderKind {
        didSet {
            guard provider != oldValue else { return }
            // 换服务商时模型与地址都得跟着换，否则会拿 A 家的模型名去请求 B 家
            model = provider.defaultModel
            baseURLText = provider.defaultBaseURL.absoluteString
            apiKey = KeychainStore.read(KeychainStore.key(for: provider)) ?? ""
            onChange?()
        }
    }

    var model: String { didSet { if model != oldValue { onChange?() } } }
    var baseURLText: String { didSet { if baseURLText != oldValue { onChange?() } } }
    var apiKey: String { didSet { if apiKey != oldValue { onChange?() } } }
    var systemPrompt: String { didSet { if systemPrompt != oldValue { onChange?() } } }

    var availableModels: [String] { provider.availableModels }

    /// 只露首 4 尾 4，中间打码
    var maskedAPIKey: String {
        guard !apiKey.isEmpty else { return "未配置" }
        guard apiKey.count > 12 else { return String(repeating: "*", count: apiKey.count) }
        return "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
    }

    init(settings: AppSettings) {
        self.settings = settings
        self.provider = settings.provider
        self.model = settings.model
        self.baseURLText = settings.baseURL.absoluteString
        self.apiKey = settings.apiKey
        self.systemPrompt = settings.systemPrompt
    }

    func save() {
        settings.provider = provider
        settings.model = model
        if let url = URL(string: baseURLText) { settings.baseURL = url }
        settings.systemPrompt = systemPrompt
        try? settings.setAPIKey(apiKey)
    }

    /// 发一条极短的请求验证 Key 与地址是否可用
    func testConnection() async -> Result<Void, ChatError> {
        guard !apiKey.isEmpty else { return .failure(.missingAPIKey) }
        guard let url = URL(string: baseURLText) else {
            return .failure(.decoding("地址格式不正确"))
        }

        let config = ProviderConfig(kind: provider, baseURL: url, apiKey: apiKey, model: model)
        let provider = NetworkChatProvider(config: config)
        let request = ChatRequest(model: model,
                                  messages: [ChatMessage(role: .user, content: "hi")],
                                  system: nil, temperature: 0, maxTokens: 8)
        do {
            for try await _ in provider.stream(request) {
                return .success(())    // 收到任意一个 chunk 就算通了
            }
            return .success(())
        } catch {
            return .failure(ChatError.from(error))
        }
    }
}
