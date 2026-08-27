import Foundation

struct AnthropicAdapter: ProviderAdapter {

    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        let body = AnthropicDTO.RequestBody(
            model: request.model,
            messages: request.messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            system: (request.system?.isEmpty == false) ? request.system : nil,
            stream: true,
            temperature: request.temperature,
            max_tokens: request.maxTokens
        )

        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("v1/messages"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        urlRequest.timeoutInterval = 60
        return urlRequest
    }

    func makeMapper() -> SSEChunkMapper { AnthropicChunkMapper() }
}

/// mapper 需要持有状态，但不是为了判断增量类型——文本增量还是思考增量，
/// 每个 `content_block_delta` 事件自己的 `delta.type`（`text_delta` /
/// `thinking_delta`）就足够区分，不依赖前面出现过的 `content_block_start`
/// （`AnthropicDTO.ContentBlockStart` 目前定义了但没有任何地方解码它）。
/// 真正需要跨事件累积的是 token 用量：`message_start` 给出 `input_tokens`，
/// `message_delta` 陆续给出 `output_tokens` 与 `stop_reason`，两者分属不同
/// 事件，必须存下来才能在每次 `message_delta` 时拼出完整的 `TokenUsage`。
struct AnthropicChunkMapper: SSEChunkMapper {

    private var inputTokens: Int = 0
    private var outputTokens: Int = 0
    private var stopReason: String?

    mutating func map(_ event: SSEEvent) throws -> [StreamChunk] {
        let data = Data(event.data.utf8)
        let decoder = JSONDecoder()

        switch event.event {
        case "message_start":
            // JSON 本身解析失败要显式抛错；JSON 合法但 usage 字段缺失是正常情况，走默认值 0。
            guard let payload = try? decoder.decode(AnthropicDTO.MessageStart.self, from: data) else {
                throw ChatError.decoding(event.data)
            }
            inputTokens = payload.message?.usage?.input_tokens ?? 0
            return []

        case "content_block_delta":
            guard let payload = try? decoder.decode(AnthropicDTO.ContentBlockDelta.self, from: data),
                  let delta = payload.delta else {
                throw ChatError.decoding(event.data)
            }
            switch delta.type {
            case "text_delta":
                guard let text = delta.text, !text.isEmpty else { return [] }
                return [.textDelta(text)]
            case "thinking_delta":
                guard let thinking = delta.thinking, !thinking.isEmpty else { return [] }
                return [.reasoningDelta(thinking)]
            default:
                // signature_delta 等类型对 UI 无意义，忽略
                return []
            }

        case "message_delta":
            // JSON 本身解析失败要显式抛错，避免吐出基于陈旧值拼出的幽灵用量事件；
            // JSON 合法但 delta/usage 字段缺失是正常情况，沿用旧值。
            guard let payload = try? decoder.decode(AnthropicDTO.MessageDelta.self, from: data) else {
                throw ChatError.decoding(event.data)
            }
            if let reason = payload.delta?.stop_reason { stopReason = reason }
            outputTokens = payload.usage?.output_tokens ?? outputTokens
            return [.usage(TokenUsage(prompt: inputTokens, completion: outputTokens))]

        case "message_stop":
            return [.done(finishReason: stopReason)]

        case "error":
            let payload = try? decoder.decode(AnthropicDTO.ErrorEnvelope.self, from: data)
            throw ChatError.serverError(status: 200, message: payload?.error?.message)

        default:
            // content_block_start / content_block_stop / ping 无需产出事件
            return []
        }
    }
}
