import Foundation

/// 一个 Server-Sent Event。
/// `event` 为 nil 表示服务端未指定类型（OpenAI 兼容协议就是这种）。
struct SSEEvent: Equatable, Sendable {
    var event: String?
    var data: String
    var id: String?
    var retry: Int?
}
