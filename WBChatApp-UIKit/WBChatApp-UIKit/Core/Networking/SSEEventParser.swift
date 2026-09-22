import Foundation

/// 把字节流增量解析成 SSE 事件。
///
/// 只做协议解析，不碰网络，因此可以逐字节喂入做单元测试。
/// 三个必须处理的边界：
/// 1. 粘包：一次 `Data` 里有多个完整事件；
/// 2. 分包：一个事件被切成多段，甚至 UTF-8 多字节字符被从中劈开；
/// 3. 换行：`\n` / `\r\n` / `\r` 都算行结束，且 `\r\n` 可能被切在两次回调之间。
final class SSEEventParser {

    /// 尚未切出完整行的原始字节。按字节缓冲而非按字符串缓冲，
    /// 才能保证多字节字符被劈开时不会解码出替换字符。
    private var byteBuffer: [UInt8] = []
    /// 单独消费 CR 后，下一字节若为 LF，则它只是同一个 CRLF 的后半段。
    private var shouldSkipLeadingLF = false

    private var eventType: String?
    private var dataLines: [String] = []
    private var lastEventID: String?
    private var retry: Int?

    func consume(_ data: Data) -> [SSEEvent] {
        data.flatMap { consume(byte: $0) }
    }

    func consume(byte: UInt8) -> [SSEEvent] {
        if shouldSkipLeadingLF {
            shouldSkipLeadingLF = false
            if byte == 0x0A { return [] }
        }
        guard byte == 0x0A || byte == 0x0D else {
            byteBuffer.append(byte)
            return []
        }
        shouldSkipLeadingLF = byte == 0x0D
        let line = String(decoding: byteBuffer, as: UTF8.self)
        byteBuffer.removeAll(keepingCapacity: true)
        return handle(line: line).map { [$0] } ?? []
    }

    /// 流结束时调用，冲刷末尾没有空行收尾的残留事件。
    func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !byteBuffer.isEmpty {
            let line = String(decoding: byteBuffer, as: UTF8.self)
            byteBuffer.removeAll()
            if let event = handle(line: line) {
                events.append(event)
            }
        }
        if let event = dispatch() {
            events.append(event)
        }
        return events
    }

    // MARK: - 私有

    /// 处理一整行，返回本行触发派发的事件（若有）
    private func handle(line: String) -> SSEEvent? {
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil          // 注释行
        }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            // 规范：值前有且仅有一个空格时剥离
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event": eventType = value
        case "data":  dataLines.append(value)
        case "id":    lastEventID = value
        case "retry": retry = Int(value)
        default:      break      // 未知字段按规范忽略
        }
        return nil
    }

    /// 空行触发派发。没有攒到任何 data 就什么都不产生。
    private func dispatch() -> SSEEvent? {
        defer {
            eventType = nil
            dataLines.removeAll()
            retry = nil
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventType,
                        data: dataLines.joined(separator: "\n"),
                        id: lastEventID,
                        retry: retry)
    }
}
