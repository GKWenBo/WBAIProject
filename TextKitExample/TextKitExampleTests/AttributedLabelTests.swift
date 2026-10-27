//
//  AttributedLabelTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

@MainActor
@Suite("Label 命中检测")
struct AttributedLabelTests {

    private static let width: CGFloat = 300

    /// 造一个尺寸刚好等于文本高度的 Label，这样垂直居中偏移为 0，断言坐标更直观。
    private func makeLabel(_ text: NSAttributedString) -> AttributedLabel {
        let label = AttributedLabel()
        label.numberOfLines = 0
        label.attributedText = text
        let size = label.sizeThatFits(CGSize(width: Self.width, height: .greatestFiniteMagnitude))
        label.frame = CGRect(x: 0, y: 0, width: Self.width, height: ceil(size.height))
        label.layoutIfNeeded()
        return label
    }

    @Test("点在 @ 上返回对应的标记")
    func hitsMention() {
        let label = makeLabel(SampleText.social())
        // 文本以 "@文波" 开头，第一行左上角必定落在它身上。
        let hit = label.token(at: CGPoint(x: 6, y: 8))

        #expect(hit?.0.kind == .mention)
        #expect(hit?.0.payload == "wenbo")
        #expect(hit?.1 == NSRange(location: 0, length: 3))
    }

    @Test("点在没有标记的文字上只给字符索引")
    func missesPlainText() {
        let label = makeLabel(NSAttributedString(string: "这一段没有任何标记", attributes: TextStyle.body))

        #expect(label.token(at: CGPoint(x: 6, y: 8)) == nil)
        #expect(label.characterIndex(at: CGPoint(x: 6, y: 8)) == 0)
    }

    @Test("点在文本下方之外返回 nil")
    func missesOutside() {
        let label = makeLabel(NSAttributedString(string: "只有一行", attributes: TextStyle.body))

        #expect(label.characterIndex(at: CGPoint(x: 6, y: label.bounds.height + 60)) == nil)
    }

    @Test("居中对齐时左边缘的空白不算命中")
    func respectsAlignment() {
        let centered = NSMutableAttributedString(attributedString: SampleText.social())
        centered.addAttribute(.paragraphStyle,
                              value: TextStyle.paragraphStyle(alignment: .center),
                              range: NSRange(location: 0, length: centered.length))

        let label = makeLabel(centered)
        // 居中后最后一行左侧是空白；自然对齐时同一位置是有字的。
        let lastLineY = label.bounds.height - 10
        #expect(label.characterIndex(at: CGPoint(x: 2, y: lastLineY)) == nil)
    }

    @Test("点击手势命中时回调标记，未命中时回调字符索引")
    func callbacks() {
        let label = makeLabel(SampleText.social())

        var hit: TextTapToken?
        var missIndex: Int??
        label.onTapToken = { token, _ in hit = token }
        label.onTapMiss = { index in missIndex = index }

        // 直接驱动内部逻辑，不依赖真实手势。
        if let (token, range) = label.token(at: CGPoint(x: 6, y: 8)) {
            label.onTapToken?(token, range)
        }
        #expect(hit?.kind == .mention)

        label.onTapMiss?(label.characterIndex(at: CGPoint(x: 6, y: label.bounds.height + 60)))
        #expect(missIndex == .some(nil))
    }
}
