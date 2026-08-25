import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("SSE 事件解析")
struct SSEEventParserTests {

    private func parse(_ chunks: [String]) -> [SSEEvent] {
        let parser = SSEEventParser()
        var events: [SSEEvent] = []
        for chunk in chunks {
            events += parser.consume(Data(chunk.utf8))
        }
        events += parser.finish()
        return events
    }

    @Test("单个完整事件")
    func singleEvent() {
        let events = parse(["data: hello\n\n"])
        #expect(events == [SSEEvent(event: nil, data: "hello", id: nil, retry: nil)])
    }

    @Test("粘包：一次 Data 含两个事件")
    func twoEventsInOneChunk() {
        let events = parse(["data: a\n\ndata: b\n\n"])
        #expect(events.map(\.data) == ["a", "b"])
    }

    @Test("分包：一个事件被切成多段")
    func eventSplitAcrossChunks() {
        let events = parse(["data: hel", "lo wor", "ld\n", "\n"])
        #expect(events.map(\.data) == ["hello world"])
    }

    @Test("UTF-8 多字节字符被劈开也能正确还原")
    func splitMultiByteCharacter() {
        // “你好” 的 UTF-8 是 6 字节，在第 2 字节处切开
        let full = Array("data: 你好\n\n".utf8)
        let parser = SSEEventParser()
        var events = parser.consume(Data(full[0..<8]))
        events += parser.consume(Data(full[8...]))
        events += parser.finish()
        #expect(events.map(\.data) == ["你好"])
    }

    @Test("支持 CRLF 与单独 CR 作为换行")
    func lineEndings() {
        #expect(parse(["data: a\r\n\r\n"]).map(\.data) == ["a"])
        #expect(parse(["data: b\r\r"]).map(\.data) == ["b"])
    }

    @Test("CRLF 被切在中间不会被误判成两个换行")
    func crlfSplitAcrossChunks() {
        let events = parse(["data: a\r", "\n\r\n"])
        #expect(events.map(\.data) == ["a"])
    }

    @Test("注释行被忽略")
    func commentIgnored() {
        let events = parse([": ping\ndata: a\n\n"])
        #expect(events.map(\.data) == ["a"])
    }

    @Test("event 与 data 组合，Anthropic 风格")
    func eventAndData() {
        let events = parse(["event: content_block_delta\ndata: {\"x\":1}\n\n"])
        #expect(events.count == 1)
        #expect(events[0].event == "content_block_delta")
        #expect(events[0].data == "{\"x\":1}")
    }

    @Test("多行 data 用换行拼接")
    func multiLineData() {
        let events = parse(["data: line1\ndata: line2\n\n"])
        #expect(events.map(\.data) == ["line1\nline2"])
    }

    @Test("值前的单个空格被剥离，其余空格保留")
    func spaceStripping() {
        #expect(parse(["data:  a\n\n"]).map(\.data) == [" a"])
        #expect(parse(["data:a\n\n"]).map(\.data) == ["a"])
    }

    @Test("id 与 retry 字段")
    func idAndRetry() {
        let events = parse(["id: 7\nretry: 3000\ndata: a\n\n"])
        #expect(events[0].id == "7")
        #expect(events[0].retry == 3000)
    }

    @Test("finish 冲刷结尾没有空行的残留事件")
    func finishFlushesTrailingEvent() {
        let events = parse(["data: tail\n"])
        #expect(events.map(\.data) == ["tail"])
    }

    @Test("只有空行不产生事件")
    func blankLinesProduceNothing() {
        #expect(parse(["\n\n\n"]).isEmpty)
    }

    @Test("finish 冲刷时，落在缓冲区末尾的孤立 CR 不应烙进 data 值")
    func finishStripsTrailingLoneCRFromData() {
        // "data: a\r" 里的 \r 落在缓冲区末尾，consume 阶段无法判定它是单独的
        // CR 还是 CRLF 的前半，只能留给 finish 收尾。finish 冲刷残留字节时
        // 必须先剥掉这个悬而未决的 \r，否则它会被整段解码进 data 字段的值。
        let events = parse(["data: a\r"])
        #expect(events.map(\.data) == ["a"])
    }

    @Test("finish 冲刷时，落在缓冲区末尾的孤立 CR 不应烙进 event 字段")
    func finishStripsTrailingLoneCRFromEvent() {
        // 整段落在缓冲区里的 "event: ping\rdata: x\r"：
        // 第一个 \r 后面紧跟 'd'（不是 \n），consume 阶段能正常判定为单独 CR，
        // 正确切出 "event: ping" 这一行；但第二个 \r 落在缓冲区末尾，
        // 只能留给 finish 处理。若 finish 不剥离它，"data: x\r" 会被整段
        // 解码，污染 data 字段（附带验证 event 字段本身在正常路径下不受影响）。
        let events = parse(["event: ping\rdata: x\r"])
        #expect(events.count == 1)
        #expect(events[0].event == "ping")
        #expect(events[0].data == "x")
    }

    @Test("finish 冲刷时，落在缓冲区末尾的孤立 CR 不应让 retry 静默丢失")
    func finishStripsTrailingLoneCRFromRetry() {
        // "retry: 3000\r" 的 \r 落在缓冲区末尾，consume 阶段无法判定，
        // 残留到 finish。若不剥离，整段解码出的 value 是 "3000\r"，
        // Int("3000\r") 返回 nil，retry 会被静默丢弃而不是报错。
        let events = parse(["data: x\nretry: 3000\r"])
        #expect(events.count == 1)
        #expect(events[0].data == "x")
        #expect(events[0].retry == 3000)
    }
}
