//
//  IncrementalTextRendererTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

/// 两套渲染器跑同一组断言：结果文本正确、追加是增量的、全量替换会重排全部。
@MainActor
@Suite("增量文本渲染器")
struct IncrementalTextRendererTests {

    private static let width: CGFloat = 300

    private static func makeTextKit1() -> IncrementalTextRenderer {
        let renderer = TextKit1IncrementalRenderer()
        renderer.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        return renderer
    }

    private static func makeTextKit2() -> IncrementalTextRenderer {
        let renderer = TextKit2IncrementalRenderer()
        renderer.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        return renderer
    }

    /// 把整篇流式文本一块块追加进去，返回最后一次追加的报告。
    @discardableResult
    private func streamAll(into renderer: IncrementalTextRenderer) -> IncrementalUpdateReport? {
        var source = StreamingTextSource(text: SampleText.streamingAnswer)
        var last: IncrementalUpdateReport?
        while let chunk = source.next() {
            last = renderer.append(NSAttributedString(string: chunk, attributes: TextStyle.body))
        }
        return last
    }

    private var fullLength: Int { (SampleText.streamingAnswer as NSString).length }

    @Test("逐块追加后的全文与原文一致", arguments: [true, false])
    func appendProducesFullText(useTextKit1: Bool) {
        let renderer = useTextKit1 ? Self.makeTextKit1() : Self.makeTextKit2()
        streamAll(into: renderer)

        #expect(renderer.string == SampleText.streamingAnswer)
    }

    @Test("TextKit 1：追加只重排尾部几行，全量替换从第 0 个字符重排")
    func textKit1IsIncremental() throws {
        let renderer = Self.makeTextKit1()
        let lastAppend = try #require(streamAll(into: renderer))

        #expect(lastAppend.totalLength == fullLength)
        #expect(lastAppend.relaidCharacters > 0)
        #expect(lastAppend.relaidCharacters < fullLength / 4)
        #expect(lastAppend.relaidUnits <= 2)

        let replace = renderer.replaceAll(with: NSAttributedString(string: SampleText.streamingAnswer,
                                                                   attributes: TextStyle.body))
        #expect(replace.relaidCharacters == fullLength)
        #expect(replace.relaidUnits > lastAppend.relaidUnits)
    }

    @Test("TextKit 2：追加只重建最后一段，全量替换重建所有段落")
    func textKit2IsIncremental() throws {
        let renderer = Self.makeTextKit2()
        let lastAppend = try #require(streamAll(into: renderer))
        let paragraphCount = SampleText.streamingAnswer.components(separatedBy: "\n").count

        #expect(lastAppend.totalLength == fullLength)
        #expect(lastAppend.relaidUnits == 1)
        #expect(lastAppend.relaidCharacters < fullLength / 2)

        let replace = renderer.replaceAll(with: NSAttributedString(string: SampleText.streamingAnswer,
                                                                   attributes: TextStyle.body))
        #expect(replace.relaidUnits == paragraphCount)
        #expect(replace.relaidCharacters == fullLength)
    }

    @Test("replaceTail 只替换尾块：前面的内容与属性不变，尾块属性被完整重建", arguments: [true, false])
    func replaceTailKeepsFrozenBlocks(useTextKit1: Bool) {
        let renderer = useTextKit1 ? Self.makeTextKit1() : Self.makeTextKit2()
        let frozen = "已闭合的第一段\n"
        _ = renderer.append(NSAttributedString(string: frozen, attributes: TextStyle.body))
        let tailStart = (frozen as NSString).length

        // 尾块先以普通文本出现，随后"闭合"后整体重渲染成粗体。
        _ = renderer.append(NSAttributedString(string: "尾块 **加粗", attributes: TextStyle.body))
        let bold = [NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 16)]
        let report = renderer.replaceTail(from: tailStart,
                                          with: NSAttributedString(string: "尾块加粗", attributes: bold))

        #expect(renderer.string == frozen + "尾块加粗")
        #expect(report.relaidCharacters <= (("尾块加粗") as NSString).length + 1)

        // 越界的起点会被收敛，不崩溃。
        let clamped = renderer.replaceTail(from: 9999, with: NSAttributedString(string: "!", attributes: bold))
        #expect(clamped.totalLength == tailStart + 4 + 1)
    }

    @Test("reset 之后清空，可以重新开始", arguments: [true, false])
    func resetClears(useTextKit1: Bool) {
        let renderer = useTextKit1 ? Self.makeTextKit1() : Self.makeTextKit2()
        streamAll(into: renderer)
        renderer.reset()

        #expect(renderer.string.isEmpty)

        let report = renderer.append(NSAttributedString(string: "重新开始", attributes: TextStyle.body))
        #expect(report.totalLength == 4)
        #expect(renderer.string == "重新开始")
    }
}
