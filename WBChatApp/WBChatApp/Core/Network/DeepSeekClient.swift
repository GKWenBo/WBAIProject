//
//  DeepSeekClient.swift
//  WBChatApp
//

import Foundation

/// 聊天流式客户端抽象，便于注入 Mock 在未配置 API Key 时演示完整交互
protocol ChatStreaming {
    func streamChat(
        messages: [ChatMessagePayload],
        config: DeepSeekConfig
    ) -> AsyncThrowingStream<StreamChunk, Error>
}

/// DeepSeek 流式客户端
///
/// 走 OpenAI 兼容的 `POST /chat/completions`（`stream: true`），
/// 用 `URLSession.bytes(for:)` 逐行读取 SSE，经 `SSEParser` 解析后
/// 通过 `AsyncThrowingStream` 吐增量给上层；消费方取消时自动断开请求。
final class DeepSeekClient: ChatStreaming {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamChat(
        messages: [ChatMessagePayload],
        config: DeepSeekConfig
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try Self.makeRequest(messages: messages, config: config)
                    let (bytes, response) = try await self.session.bytes(for: request)
                    try await Self.validate(response: response, bytes: bytes)

                    for try await line in bytes.lines {
                        guard let event = SSEParser.parse(line: line) else { continue }
                        switch event {
                        case .chunk(let chunk):
                            continuation.yield(chunk)
                        case .done:
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    private nonisolated static func makeRequest(
        messages: [ChatMessagePayload],
        config: DeepSeekConfig
    ) throws -> URLRequest {
        let url = config.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

        let body = ChatCompletionRequest(
            model: config.model,
            messages: messages,
            stream: true,
            temperature: config.temperature
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// 非 200 时正文不是 SSE，读完整个 body 提取服务端错误信息
    private static func validate(response: URLResponse, bytes: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard http.statusCode != 200 else { return }

        var body = ""
        for try await line in bytes.lines {
            body += line
        }
        throw APIError.server(statusCode: http.statusCode, message: Self.errorMessage(fromBody: body))
    }

    private nonisolated static func errorMessage(fromBody body: String) -> String? {
        struct ErrorEnvelope: Decodable {
            struct Payload: Decodable {
                let message: String?
            }
            let error: Payload?
        }
        guard let data = body.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) else {
            return nil
        }
        return envelope.error?.message
    }
}
