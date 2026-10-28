//
//  StreamingTextSourceTests.swift
//  TextKitExampleTests
//

import Testing
@testable import TextKitExample

@Suite("流式文本源")
struct StreamingTextSourceTests {

    @Test("所有块拼起来等于原文，块大小按序列循环")
    func chunksReassembleToOriginal() {
        var source = StreamingTextSource(text: "abcdefghij", chunkPattern: [3, 1])
        var chunks: [String] = []
        while let chunk = source.next() { chunks.append(chunk) }

        #expect(chunks == ["abc", "d", "efg", "h", "ij"])
        #expect(chunks.joined() == "abcdefghij")
        #expect(source.isFinished)
        #expect(source.next() == nil)
    }

    @Test("按字素簇切分，emoji 不会被劈开")
    func doesNotSplitGraphemes() {
        var source = StreamingTextSource(text: "好👍🏻📈", chunkPattern: [1])

        #expect(source.next() == "好")
        #expect(source.next() == "👍🏻")
        #expect(source.next() == "📈")
        #expect(source.next() == nil)
    }

    @Test("emitted 是已经吐出的部分，reset 回到开头")
    func emittedAndReset() {
        var source = StreamingTextSource(text: "流式输出", chunkPattern: [2])
        _ = source.next()
        #expect(source.emitted == "流式")

        source.reset()
        #expect(source.emitted.isEmpty)
        #expect(source.isFinished == false)
        #expect(source.next() == "流式")
    }

    @Test("空文本一开始就是结束状态")
    func emptyText() {
        var source = StreamingTextSource(text: "")
        #expect(source.isFinished)
        #expect(source.next() == nil)
    }
}
