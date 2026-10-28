import Foundation

/// 一个 Server-Sent Event。
/// `event` 为 nil 表示服务端未指定类型（OpenAI 兼容协议就是这种）。
struct SSEEvent: Equatable, Sendable {
    var event: String?
    /// 多行 data 以 `\n` 拼接后的内容
    var data: String
    var id: String?
    /// 服务端建议的重连间隔（毫秒），当前未使用
    var retry: Int?
}
