import Foundation

/// 全工程统一的错误类型：网络、协议、存储、并发限制等错误都归一到这里。
enum ChatError: Error, Equatable {
    case missingAPIKey
    /// 401 / 403
    case unauthorized
    /// 429，retryAfter 来自响应头 Retry-After
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(status: Int, message: String?)
    case network(code: Int)
    /// 网络空闲、语义无进展或总时长超时
    case timeout
    /// 报文无法解析，关联值为原始内容
    case decoding(String)
    /// 连接已断开但没收到停止原因
    case interruptedStream
    /// 落库失败
    case storage
    /// 同时生成的会话数达到上限
    case generationLimit
    /// 用户主动停止
    case cancelled

    /// 所有面向用户的文案集中在这里，便于后续本地化。
    var userMessage: String {
        switch self {
        case .missingAPIKey:
            return "还没有配置 API Key，去设置里填一个吧"
        case .unauthorized:
            return "API Key 无效或已过期，请检查设置"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "请求太频繁了，请 \(Int(seconds)) 秒后再试"
            }
            return "请求太频繁了，稍后再试"
        case .serverError(let status, let message):
            if let message, !message.isEmpty {
                return "服务端错误（\(status)）：\(message)"
            }
            return "服务端错误（\(status)）"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .timeout:
            return "请求超时，请重试"
        case .decoding:
            return "响应格式无法识别"
        case .interruptedStream:
            return "连接已结束，但回复尚未完整生成"
        case .storage:
            return "内容尚未保存，请重试保存"
        case .generationLimit:
            return "已有三个会话正在生成，请等待完成或停止其中一个"
        case .cancelled:
            return "已停止生成"
        }
    }

    /// 把 URLError 归一到 ChatError
    static func from(_ error: Error) -> ChatError {
        if let chatError = error as? ChatError { return chatError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .timedOut:  return .timeout
            default:         return .network(code: urlError.errorCode)
            }
        }
        if error is DecodingError {
            return .decoding(String(describing: error))
        }
        return .network(code: (error as NSError).code)
    }
}
