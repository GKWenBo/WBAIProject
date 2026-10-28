import Foundation

/// API Key 输入的处理结果
enum APIKeyInputResult: Equatable {
    /// 输入为空（或只有空白），保持原 Key
    case unchanged
    case updated
    /// 内容不像 Key，未保存；关联值为给用户的提示
    case invalid(String)
}

/// 设置页：编辑的是 AppSettings 的草稿副本，调用 save() 才落盘。
@MainActor
final class SettingsViewModel {

    /// 任一字段变化时通知页面刷新
    var onChange: (() -> Void)?

    private let settings: AppSettings
    private let catalog: ModelCatalogProviding

    /// 切换服务商、远端刷新时会级联修改多个字段，
    /// 这期间抑制各自的 onChange，结尾只统一发一次，避免连续 reload。
    private var isBatchingChanges = false

    var provider: ProviderKind {
        didSet {
            guard provider != oldValue else { return }
            // 换服务商时模型与地址都得跟着换，否则会拿 A 家的模型名去请求 B 家
            isBatchingChanges = true
            availableModels = catalog.cachedModels(for: provider)
            model = availableModels.first?.id ?? provider.defaultModel
            baseURLText = provider.defaultBaseURL.absoluteString
            apiKey = settings.apiKey(for: provider)
            isBatchingChanges = false
            onChange?()
            scheduleModelRefresh()
        }
    }

    var model: String { didSet { if model != oldValue { notifyChange() } } }
    var baseURLText: String {
        didSet {
            guard baseURLText != oldValue else { return }
            notifyChange()
            if !isBatchingChanges { scheduleModelRefresh() }
        }
    }
    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            notifyChange()
            if !isBatchingChanges { scheduleModelRefresh() }
        }
    }
    var systemPrompt: String { didSet { if systemPrompt != oldValue { notifyChange() } } }

    private func notifyChange() {
        guard !isBatchingChanges else { return }
        onChange?()
    }

    /// 设置页展示的模型（最多 3 个）：先用缓存或本地兜底，远端拉取成功后覆盖
    private(set) var availableModels: [ModelInfo]
    /// 是否正在拉取远端模型列表
    private(set) var isLoadingModels = false

    /// 每次刷新递增，晚到的旧结果据此丢弃（如快速连续切换服务商）
    private var refreshGeneration = 0
    private var refreshTask: Task<Void, Never>?

    /// 只露首 4 尾 4，中间打码
    var maskedAPIKey: String {
        guard !apiKey.isEmpty else { return "未配置" }
        guard apiKey.count > 12 else { return String(repeating: "*", count: apiKey.count) }
        return "\(apiKey.prefix(4))****\(apiKey.suffix(4))"
    }

    init(settings: AppSettings, catalog: ModelCatalogProviding) {
        self.settings = settings
        self.catalog = catalog
        let models = catalog.cachedModels(for: settings.provider)
        self.availableModels = models
        self.provider = settings.provider
        // 旧版本存下的模型若既不在缓存也不在本地清单（如已下线的 deepseek-chat），换成推荐第一个
        let knownIDs = Set((models + BundledModelCatalog.models(for: settings.provider)).map(\.id))
        self.model = knownIDs.contains(settings.model)
            ? settings.model
            : (models.first?.id ?? settings.provider.defaultModel)
        self.baseURLText = settings.baseURL.absoluteString
        self.apiKey = settings.apiKey
        self.systemPrompt = settings.systemPrompt
    }

    /// 在后台刷新模型列表，取消上一次尚未完成的刷新
    func scheduleModelRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in await self?.refreshModels() }
    }

    /// 先展示缓存/兜底，再用当前填写的 Key 拉远端；无 Key 或失败时保持兜底列表。
    /// 远端成功且当前模型已不在远端列表（已下线）时，自动切到推荐的第一个。
    func refreshModels() async {
        refreshGeneration += 1
        let generation = refreshGeneration
        availableModels = catalog.cachedModels(for: provider)

        guard !apiKey.isEmpty, let url = URL(string: baseURLText) else {
            isLoadingModels = false
            onChange?()
            return
        }
        isLoadingModels = true
        onChange?()

        let config = ProviderConfig(kind: provider, baseURL: url, apiKey: apiKey, model: model)
        let remote = try? await catalog.fetchLatestModels(config: config)
        guard generation == refreshGeneration else { return }

        isBatchingChanges = true
        isLoadingModels = false
        if let remote, !remote.recommended.isEmpty {
            availableModels = remote.recommended
            if !remote.allIDs.contains(model) {
                model = remote.recommended[0].id
            }
        }
        isBatchingChanges = false
        onChange?()
    }

    /// 输入框留空表示“不修改”，避免用户误触空输入把已保存的真实 Key 清空。
    /// 真要清空，需通过 clearAPIKey() 显式操作。
    ///
    /// 输入框是密文的，粘错内容（如剪贴板里还是刚复制的代码块）用户看不到，
    /// 所以这里先去掉首尾空白，再校验只含可打印 ASCII 且无空白，不合法就拒绝落盘。
    @discardableResult
    func updateAPIKeyIfProvided(_ input: String) -> APIKeyInputResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unchanged }
        guard AppSettings.isPlausibleAPIKey(trimmed) else {
            return .invalid("内容包含空格、换行或中文等字符，不像是 API Key。请确认剪贴板里是 Key 后重新粘贴")
        }
        apiKey = trimmed
        return .updated
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
