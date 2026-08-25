import Foundation

/// 上层唯一依赖的抽象：给一个请求，吐一串统一事件。
protocol ChatProvider: Sendable {
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error>
}

/// 把某家服务商的 SSE 事件映射成统一事件。
/// 用 mutating 是因为 Anthropic 需要记住当前 content_block 的类型。
protocol SSEChunkMapper {
    mutating func map(_ event: SSEEvent) throws -> [StreamChunk]
}

/// 一家服务商的全部协议差异，收敛在这一个类型里。
protocol ProviderAdapter: Sendable {
    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest
    func makeMapper() -> SSEChunkMapper
}
