import Foundation

/// OpenAI 兼容协议（OpenAI 本家与 DeepSeek 共用）。
struct OpenAICompatibleAdapter: ProviderAdapter {

    func buildRequest(_ request: ChatRequest, config: ProviderConfig) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw ChatError.missingAPIKey }

        var messages: [OpenAIDTO.RequestBody.Message] = []
        // OpenAI 兼容协议把 system 当成 messages 里的第一条
        if let system = request.system, !system.isEmpty {
            messages.append(.init(role: ChatRole.system.rawValue, content: system))
        }
        messages += request.messages.map {
            .init(role: $0.role.rawValue, content: $0.content)
        }

        let body = OpenAIDTO.RequestBody(
            model: request.model,
            messages: messages,
            stream: true,
            temperature: request.temperature,
            max_tokens: request.maxTokens,
            stream_options: .init(include_usage: true)
        )

        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("v1/chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(body)
        urlRequest.timeoutInterval = 60
        return urlRequest
    }

    func makeMapper() -> SSEChunkMapper { OpenAIChunkMapper() }
}

/// OpenAI 兼容协议的 SSE 映射：无状态，每帧 `data` 独立解析，`[DONE]` 为结束标记。
struct OpenAIChunkMapper: SSEChunkMapper {

    mutating func map(_ event: SSEEvent) throws -> [StreamChunk] {
        let payload = event.data.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return [] }
        if payload == "[DONE]" { return [.done(finishReason: nil)] }

        let response: OpenAIDTO.StreamResponse
        do {
            response = try JSONDecoder().decode(OpenAIDTO.StreamResponse.self,
                                                from: Data(payload.utf8))
        } catch {
            throw ChatError.decoding(payload)
        }

        var chunks: [StreamChunk] = []
        if let choice = response.choices?.first {
            // 思考在前、正文在后，保证 UI 上思考区先于正文出现
            if let reasoning = choice.delta?.reasoning_content, !reasoning.isEmpty {
                chunks.append(.reasoningDelta(reasoning))
            }
            if let content = choice.delta?.content, !content.isEmpty {
                chunks.append(.textDelta(content))
            }
            if let usage = response.usage {
                chunks.append(.usage(TokenUsage(prompt: usage.prompt_tokens,
                                                completion: usage.completion_tokens)))
            }
            if let reason = choice.finish_reason {
                chunks.append(.finishReason(reason))
            }
        } else if let usage = response.usage {
            // 有些实现把 usage 单独放一帧，此时 choices 为空数组
            chunks.append(.usage(TokenUsage(prompt: usage.prompt_tokens,
                                            completion: usage.completion_tokens)))
        }
        return chunks
    }
}
