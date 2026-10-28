import Foundation
import Testing
@testable import WBChatApp_UIKit

/// 模型列表专用的 URLProtocol 桩，与 `StubURLProtocol` 分开，避免和网络传输层测试并行时互相覆盖。
final class ModelListStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = ""
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset(body: String, status: Int = 200) {
        responseBody = body
        statusCode = status
        lastRequest = nil
    }
}

@Suite("模型目录服务", .serialized)
struct ModelCatalogServiceTests {

    private func make() -> ModelCatalogService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ModelListStubURLProtocol.self]
        let defaults = UserDefaults(suiteName: "models.test.\(UUID().uuidString)")!
        return ModelCatalogService(defaults: defaults, session: URLSession(configuration: configuration))
    }

    private func config(_ kind: ProviderKind, apiKey: String = "sk-test") -> ProviderConfig {
        ProviderConfig(kind: kind, baseURL: kind.defaultBaseURL, apiKey: apiKey, model: kind.defaultModel)
    }

    @Test("没有缓存时返回本地兜底清单")
    func cachedModelsFallBackToBundled() {
        let service = make()
        for provider in ProviderKind.allCases {
            #expect(service.cachedModels(for: provider)
                    == ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: provider)))
        }
    }

    @Test("OpenAI 兼容协议：请求 /v1/models 并按策略排序，结果写入缓存覆盖兜底")
    func openAIFetchOverridesCache() async throws {
        ModelListStubURLProtocol.reset(body: """
        {"object":"list","data":[
          {"id":"text-embedding-3-large","created":1},
          {"id":"gpt-6.1-terra","created":300},
          {"id":"gpt-7-preview","created":900},
          {"id":"gpt-6-astra","created":200}
        ]}
        """)
        let service = make()
        let result = try await service.fetchLatestModels(config: config(.openAI))

        let request = try #require(ModelListStubURLProtocol.lastRequest)
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(result.recommended.map(\.id) == ["gpt-6-astra", "gpt-6.1-terra", "gpt-7-preview"])
        #expect(result.allIDs.contains("text-embedding-3-large"))
        #expect(service.cachedModels(for: .openAI) == result.recommended)
    }

    @Test("Anthropic：x-api-key 鉴权，解析 display_name 与 created_at")
    func anthropicFetch() async throws {
        ModelListStubURLProtocol.reset(body: """
        {"data":[
          {"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","created_at":"2026-08-01T00:00:00Z"},
          {"type":"model","id":"claude-next-6","display_name":"Claude Next","created_at":"2026-10-01T00:00:00.000Z"}
        ],"has_more":false}
        """)
        let service = make()
        let result = try await service.fetchLatestModels(config: config(.anthropic))

        let request = try #require(ModelListStubURLProtocol.lastRequest)
        #expect(request.url?.path == "/v1/models")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(result.recommended.map(\.id) == ["claude-opus-5-5", "claude-next-6"])
        #expect(result.recommended[1].displayName == "Claude Next")
        #expect(result.recommended[1].createdAt != nil)
    }

    @Test("鉴权失败抛 unauthorized，缓存保持兜底")
    func unauthorizedKeepsFallback() async {
        ModelListStubURLProtocol.reset(body: #"{"error":{"message":"bad key"}}"#, status: 401)
        let service = make()
        await #expect(throws: ChatError.unauthorized) {
            try await service.fetchLatestModels(config: config(.deepSeek))
        }
        #expect(service.cachedModels(for: .deepSeek)
                == ModelSelectionPolicy.fallback(BundledModelCatalog.models(for: .deepSeek)))
    }

    @Test("没有 Key 不发请求，直接抛 missingAPIKey")
    func missingKeyDoesNotRequest() async {
        ModelListStubURLProtocol.reset(body: "{}")
        let service = make()
        await #expect(throws: ChatError.missingAPIKey) {
            try await service.fetchLatestModels(config: config(.openAI, apiKey: ""))
        }
        #expect(ModelListStubURLProtocol.lastRequest == nil)
    }

    @Test("报文无法解析时抛 decoding")
    func malformedBodyThrowsDecoding() async {
        ModelListStubURLProtocol.reset(body: "not json")
        let service = make()
        await #expect(throws: ChatError.decoding("not json")) {
            try await service.fetchLatestModels(config: config(.openAI))
        }
    }
}
