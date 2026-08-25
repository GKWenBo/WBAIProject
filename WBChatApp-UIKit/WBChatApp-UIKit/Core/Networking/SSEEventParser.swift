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

    private var eventType: String?
    private var dataLines: [String] = []
    private var lastEventID: String?
    private var retry: Int?

    func consume(_ data: Data) -> [SSEEvent] {
        byteBuffer.append(contentsOf: data)
        var events: [SSEEvent] = []

        while let terminator = nextLineTerminator() {
            let lineBytes = Array(byteBuffer[0..<terminator.lineEnd])
            byteBuffer.removeFirst(terminator.consumed)
            let line = String(decoding: lineBytes, as: UTF8.self)
            if let event = handle(line: line) {
                events.append(event)
            }
        }
        return events
    }

    /// 流结束时调用，冲刷末尾没有空行收尾的残留事件。
    func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        // consume 阶段对落在缓冲区末尾的 \r 会保守地留在缓冲区里，
        // 因为无法判断它是单独的 CR 还是被切断的 CRLF 前半。
        // 流已经结束，不会再有下一个字节来消解这个悬念，
        // 这里按“单独 CR 也是行终止符”的规范把它当结尾换行剥掉，
        // 避免它被当作残留内容烙进字段值里。
        if byteBuffer.last == 0x0D {
            byteBuffer.removeLast()
        }
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

    private struct LineTerminator {
        /// 行内容的结束下标（不含换行符本身）
        let lineEnd: Int
        /// 本行连同换行符共消耗的字节数
        let consumed: Int
    }

    private func nextLineTerminator() -> LineTerminator? {
        guard let index = byteBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) else {
            return nil
        }
        if byteBuffer[index] == 0x0D {
            // 落在缓冲区末尾的 \r 必须等下一个字节到达，
            // 否则无法区分它是单独的 CR 还是 CRLF 的前半
            if index == byteBuffer.count - 1 { return nil }
            if byteBuffer[index + 1] == 0x0A {
                return LineTerminator(lineEnd: index, consumed: index + 2)
            }
        }
        return LineTerminator(lineEnd: index, consumed: index + 1)
    }

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
