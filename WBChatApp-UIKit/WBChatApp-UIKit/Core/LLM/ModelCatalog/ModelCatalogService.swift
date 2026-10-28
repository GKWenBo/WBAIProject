import Foundation

/// 设置页依赖的模型目录抽象，测试里可替换为假实现。
protocol ModelCatalogProviding: Sendable {
    /// 同步可用的列表：上次远端结果的缓存，没有则取本地兜底清单
    func cachedModels(for provider: ProviderKind) -> [ModelInfo]
    /// 拉取远端最新模型，成功后写入缓存
    func fetchLatestModels(config: ProviderConfig) async throws -> RemoteModelCatalog
}

/// 调各服务商官方 `/v1/models`，协议差异交给对应 adapter。
/// 缓存只含模型 id 等非敏感信息，因此放在 UserDefaults。
final class ModelCatalogService: ModelCatalogProviding, @unchecked Sendable {

    private let defaults: UserDefaults
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    func cachedModels(for provider: ProviderKind) -> [ModelInfo] {
        if let data = defaults.data(forKey: Self.cacheKey(for: provider)),
           let cached = try? JSONDecoder().decode([ModelInfo].self, from: data),
           !cached.isEmpty {
            return cached
        }
        return ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: provider))
    }

    func fetchLatestModels(config: ProviderConfig) async throws -> RemoteModelCatalog {
        let adapter: ProviderAdapter = config.kind.usesAnthropicProtocol
            ? AnthropicAdapter()
            : OpenAICompatibleAdapter()
        let request = try adapter.buildModelListRequest(config: config)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ChatError.from(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403: throw ChatError.unauthorized
            case 429:      throw ChatError.rateLimited(retryAfter: nil)
            default:       throw ChatError.serverError(status: http.statusCode, message: nil)
            }
        }

        let remote = try adapter.parseModelList(data)
        let recommended = ModelSelectionPolicy.select(remote: remote,
                                                      bundled: BundledModelCatalog.models(for: config.kind))
        if let encoded = try? JSONEncoder().encode(recommended) {
            defaults.set(encoded, forKey: Self.cacheKey(for: config.kind))
        }
        return RemoteModelCatalog(recommended: recommended, allIDs: Set(remote.map(\.id)))
    }

    static func cacheKey(for provider: ProviderKind) -> String {
        "models.cache.\(provider.rawValue)"
    }
}
