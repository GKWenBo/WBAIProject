import Foundation

/// 把一次 HTTP 请求变成 SSE 事件流。
/// 负责状态码检查与字节喂给解析器，不理解任何业务语义。
enum SSEStream {

    static func events(for request: URLRequest,
                       session: URLSession) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response)

                    let parser = SSEEventParser()
                    var buffer = [UInt8]()
                    buffer.reserveCapacity(4096)

                    for try await byte in bytes {
                        buffer.append(byte)
                        // 攒到换行再交给解析器，避免每字节一次函数调用
                        if byte == 0x0A {
                            for event in parser.consume(Data(buffer)) {
                                continuation.yield(event)
                            }
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    if !buffer.isEmpty {
                        for event in parser.consume(Data(buffer)) {
                            continuation.yield(event)
                        }
                    }
                    for event in parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 非 2xx 时读出错误体再抛，尽量把服务端文案带给用户。
    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }

        switch http.statusCode {
        case 401, 403:
            throw ChatError.unauthorized
        case 429:
            let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(TimeInterval.init)
            throw ChatError.rateLimited(retryAfter: retryAfter)
        default:
            throw ChatError.serverError(status: http.statusCode, message: nil)
        }
    }
}
