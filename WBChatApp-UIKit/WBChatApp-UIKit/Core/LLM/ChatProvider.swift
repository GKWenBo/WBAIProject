import Foundation

/// 上层唯一依赖的抽象：给一个请求，吐一串统一事件。
protocol ChatProvider: Sendable {
    /// 发起流式请求；消费方取消迭代即取消底层网络任务
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error>
}

/// 把某家服务商的 SSE 事件映射成统一事件。
/// 用 mutating 是因为 Anthropic 需要跨事件累积 token 用量与停止原因。
protocol SSEChunkMapper {
    /// 一个 SSE 事件可能产出 0~N 个统一事件；报文无法解析时抛错
    mutating func map(_ event: SSEEvent) throws -> [StreamChunk]
}

/// 一家服务商的全部协议差异，收敛在这一个类型里。
protocol ProviderAdapter: Sendable {
    /// 拼装鉴权头、请求体与路径
    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest
    /// 每次请求新建一个 mapper，保证状态不跨请求
    func makeMapper() -> SSEChunkMapper
    /// 拼装拉取模型列表的请求
    func buildModelListRequest(config: ProviderConfig) throws -> URLRequest
    /// 解析模型列表响应体
    func parseModelList(_ data: Data) throws -> [ModelInfo]
}
