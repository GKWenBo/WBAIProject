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
}
