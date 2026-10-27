//
//  TruncationProbeTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

@MainActor
@Suite("截断探测")
struct TruncationProbeTests {

    private static let width: CGFloat = 300
    private static let maxLines = 3

    private var longText: NSAttributedString { SampleText.articleAttributed() }
    private var shortText: NSAttributedString {
        NSAttributedString(string: "很短的一句话", attributes: TextStyle.body)
    }

    @Test("短文本不会被截断")
    func shortTextIsNotTruncated() {
        let result = TruncationProbe.probe(shortText, width: Self.width, maxLines: Self.maxLines)

        #expect(result.isTruncated == false)
        #expect(result.lineCount == 1)
        #expect(result.truncationCharacterIndex == nil)
    }

    @Test("长文本在限定行数下被截断，且截断点落在文本范围内")
    func longTextIsTruncated() {
        let text = longText
        let result = TruncationProbe.probe(text, width: Self.width, maxLines: Self.maxLines)

        #expect(result.isTruncated)
        #expect(result.lineCount == Self.maxLines)

        let index = try! #require(result.truncationCharacterIndex)
        #expect(index > 0)
        #expect(index < text.length)
    }

    @Test("空文本和零宽度不会崩，返回未截断")
    func degenerateInput() {
        #expect(TruncationProbe.probe(NSAttributedString(), width: Self.width, maxLines: 3).isTruncated == false)
        #expect(TruncationProbe.probe(longText, width: 0, maxLines: 3).isTruncated == false)
    }

    @Test("拼上「展开」尾巴之后仍然不超过限定行数")
    func collapsedFitsWithinMaxLines() {
        let text = longText
        var attributes = TextStyle.body
        attributes[.tapToken] = TextTapToken(kind: .expand, payload: "展开")
        let suffix = NSAttributedString(string: "… 展开", attributes: attributes)

        let collapsed = TruncationProbe.collapsed(text,
                                                  suffix: suffix,
                                                  width: Self.width,
                                                  maxLines: Self.maxLines)

        #expect(collapsed.length < text.length)
        #expect(collapsed.string.hasSuffix("… 展开"))

        let after = TruncationProbe.probe(collapsed, width: Self.width, maxLines: Self.maxLines)
        #expect(after.isTruncated == false)
        #expect(after.lineCount <= Self.maxLines)
    }

    @Test("不需要截断时原样返回")
    func collapsedKeepsShortText() {
        let suffix = NSAttributedString(string: "… 展开", attributes: TextStyle.body)
        let collapsed = TruncationProbe.collapsed(shortText,
                                                  suffix: suffix,
                                                  width: Self.width,
                                                  maxLines: Self.maxLines)

        #expect(collapsed.string == shortText.string)
    }
}
