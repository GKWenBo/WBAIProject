import Foundation

/// 设置页：编辑的是 AppSettings 的草稿副本，调用 save() 才落盘。
@MainActor
final class SettingsViewModel {

    /// 任一字段变化时通知页面刷新
    var onChange: (() -> Void)?

    private let settings: AppSettings

    /// 切换服务商时会级联修改 model / baseURLText / apiKey，
    /// 这期间抑制各自的 onChange，结尾只统一发一次，避免连续 reload。
    private var isBatchingProviderSwitch = false

    var provider: ProviderKind {
        didSet {
            guard provider != oldValue else { return }
            // 换服务商时模型与地址都得跟着换，否则会拿 A 家的模型名去请求 B 家
            isBatchingProviderSwitch = true
            model = provider.defaultModel
            baseURLText = provider.defaultBaseURL.absoluteString
            apiKey = settings.apiKey(for: provider)
            isBatchingProviderSwitch = false
            onChange?()
        }
    }

    var model: String { didSet { if model != oldValue { notifyChange() } } }
    var baseURLText: String { didSet { if baseURLText != oldValue { notifyChange() } } }
    var apiKey: String { didSet { if apiKey != oldValue { notifyChange() } } }
    var systemPrompt: String { didSet { if systemPrompt != oldValue { notifyChange() } } }

    private func notifyChange() {
        guard !isBatchingProviderSwitch else { return }
        onChange?()
    }

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

    /// 输入框留空表示“不修改”，避免用户误触空输入把已保存的真实 Key 清空。
    /// 真要清空，需通过 clearAPIKey() 显式操作。
    func updateAPIKeyIfProvided(_ input: String) {
        guard !input.isEmpty else { return }
        apiKey = input
    }

    /// 显式清空 API Key，对应 UI 上的「清除 Key」操作。
    func clearAPIKey() {
        apiKey = ""
    }

    /// 保存所有设置。baseURL 格式非法时不落盘（保留旧值），并返回 false 告知调用方保存失败。
    @discardableResult
    func save() -> Bool {
        settings.provider = provider
        settings.model = model
        settings.systemPrompt = systemPrompt
        try? settings.setAPIKey(apiKey)

        guard let url = URL(string: baseURLText) else { return false }
        settings.baseURL = url
        return true
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
