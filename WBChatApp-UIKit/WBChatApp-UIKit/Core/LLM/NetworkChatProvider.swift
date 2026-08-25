import Foundation

/// 唯一的网络实现。协议差异全部由注入的 adapter 承担，
/// 因此新增一家服务商不需要改这里。
final class NetworkChatProvider: ChatProvider {

    private let adapter: ProviderAdapter
    private let config: ProviderConfig
    private let session: URLSession

    init(adapter: ProviderAdapter, config: ProviderConfig, session: URLSession = .shared) {
        self.adapter = adapter
        self.config = config
        self.session = session
    }

    /// 按当前服务商种类挑选 adapter 的便利构造
    convenience init(config: ProviderConfig, session: URLSession = .shared) {
        let adapter: ProviderAdapter = config.kind.usesAnthropicProtocol
            ? AnthropicAdapter()
            : OpenAICompatibleAdapter()
        self.init(adapter: adapter, config: config, session: session)
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let urlRequest = try adapter.buildRequest(request, config: config)
                    var mapper = adapter.makeMapper()
                    for try await event in SSEStream.events(for: urlRequest, session: session) {
                        try Task.checkCancellation()
                        for chunk in try mapper.map(event) {
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
