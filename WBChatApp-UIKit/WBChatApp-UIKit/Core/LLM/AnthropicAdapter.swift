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

/// Anthropic 的增量类型要靠上下文判断，因此 mapper 需要持有状态。
struct AnthropicChunkMapper: SSEChunkMapper {

    private var inputTokens: Int = 0
    private var outputTokens: Int = 0
    private var stopReason: String?

    mutating func map(_ event: SSEEvent) throws -> [StreamChunk] {
        let data = Data(event.data.utf8)
        let decoder = JSONDecoder()

        switch event.event {
        case "message_start":
            let payload = try? decoder.decode(AnthropicDTO.MessageStart.self, from: data)
            inputTokens = payload?.message?.usage?.input_tokens ?? 0
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
            let payload = try? decoder.decode(AnthropicDTO.MessageDelta.self, from: data)
            if let reason = payload?.delta?.stop_reason { stopReason = reason }
            outputTokens = payload?.usage?.output_tokens ?? outputTokens
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
