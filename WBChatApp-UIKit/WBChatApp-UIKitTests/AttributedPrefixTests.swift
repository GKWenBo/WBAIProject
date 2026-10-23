import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("属性串稳定前缀")
struct AttributedPrefixTests {

    private let plain: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 17),
        .foregroundColor: UIColor.label,
    ]
    private let bold: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 17),
        .foregroundColor: UIColor.label,
    ]

    private func string(_ text: String,
                        _ attributes: [NSAttributedString.Key: Any]? = nil) -> NSAttributedString {
        NSAttributedString(string: text, attributes: attributes ?? plain)
    }

    /// UTF-16 偏移是否落在字位簇边界上。实现无关的断言，不依赖
    /// `rangeOfComposedCharacterSequence` 的具体行为。
    private func isCharacterBoundary(_ text: String, _ utf16Offset: Int) -> Bool {
        if utf16Offset == 0 { return true }
        var count = 0
        for character in text {
            count += character.utf16.count
            if count == utf16Offset { return true }
            if count > utf16Offset { return false }
        }
        return count == utf16Offset
    }

    // MARK: - 基本情形

    @Test("纯追加：整个旧串都是稳定前缀")
    func pureAppend() {
        let old = string("今天天气")
        let new = string("今天天气不错")
        #expect(AttributedPrefix.stableLength(old, new) == old.length)
    }

    @Test("两串完全相同：稳定前缀是全长")
    func identical() {
        let old = string("一样的内容")
        let new = string("一样的内容")
        #expect(AttributedPrefix.stableLength(old, new) == old.length)
    }

    @Test("旧串为空：没有可复用的前缀")
    func emptyOld() {
        #expect(AttributedPrefix.stableLength(string(""), string("新内容")) == 0)
    }

    @Test("新串为空：没有可复用的前缀")
    func emptyNew() {
        #expect(AttributedPrefix.stableLength(string("旧内容"), string("")) == 0)
    }

    @Test("新串比旧串短：按较短的那个算")
    func newIsShorter() {
        let old = string("前面一段很长的内容")
        let new = string("前面一段")
        #expect(AttributedPrefix.stableLength(old, new) == new.length)
    }

    // MARK: - 属性发散

    @Test("字符相同但整段属性变了：前缀为 0")
    func sameCharactersDifferentAttributes() {
        let old = string("粗体", plain)
        let new = string("粗体", bold)
        #expect(AttributedPrefix.stableLength(old, new) == 0)
    }

    @Test("属性在中途发散：截断到发散 run 的起点")
    func divergesAtRunBoundary() {
        let old = string("abcdef", plain)
        let new = NSMutableAttributedString(string: "abc", attributes: plain)
        new.append(string("def", bold))
        // 字符公共前缀是 6，但属性从第 3 个字符起不同
        #expect(AttributedPrefix.stableLength(old, new) == 3)
    }

    @Test("旧串的 run 比新串长时取两者共同终点")
    func takesCommonRunEnd() {
        let old = string("abcdef", plain)                       // 一个 run
        let new = NSMutableAttributedString(string: "ab", attributes: plain)
        new.append(string("cd", plain))                         // 同属性，分两段写入
        new.append(string("ef", bold))
        #expect(AttributedPrefix.stableLength(old, new) == 4)
    }

    // MARK: - Markdown 追溯改写（真实渲染器）

    @Test("未闭合的加粗被闭合后，前缀不会被误判为稳定")
    func closingEmphasisRewritesPrefix() {
        let renderer = AttributedRenderer()
        func render(_ raw: String) -> NSAttributedString {
            renderer.render(MarkdownBlock(ordinal: 0, kind: .paragraph,
                                          rawText: raw, isSealed: false))
        }
        // "前**粗" 里的星号还是普通文字；补上 "**" 之后星号消失、"粗" 变加粗。
        let old = render("前**粗")
        let new = render("前**粗**")
        let stable = AttributedPrefix.stableLength(old, new)

        // 稳定前缀必须落在「前」之内，不能把后面那几个字符当成没变。
        #expect(stable <= 1)
        // 并且按这个前缀拼出来的结果必须等于全新渲染的结果。
        let spliced = NSMutableAttributedString(attributedString: old.attributedSubstring(
            from: NSRange(location: 0, length: stable)))
        spliced.append(new.attributedSubstring(
            from: NSRange(location: stable, length: new.length - stable)))
        #expect(spliced.isEqual(to: new))
    }

    @Test("流式逐字追加：拼接结果始终等于全新渲染")
    func incrementalSplicingMatchesFullRender() {
        let renderer = AttributedRenderer()
        let full = "这是一段**带格式**的文字，还有 `code` 和[链接](https://example.com)。"
        var previous = NSAttributedString()

        for length in 1...full.count {
            let raw = String(full.prefix(length))
            let current = renderer.render(MarkdownBlock(ordinal: 0, kind: .paragraph,
                                                        rawText: raw, isSealed: false))
            let stable = AttributedPrefix.stableLength(previous, current)
            #expect(stable <= previous.length)
            #expect(stable <= current.length)

            let spliced = NSMutableAttributedString(attributedString: previous.attributedSubstring(
                from: NSRange(location: 0, length: stable)))
            spliced.append(current.attributedSubstring(
                from: NSRange(location: stable, length: current.length - stable)))
            #expect(spliced.isEqual(to: current), "前缀 \(stable) 处拼接后与全新渲染不一致：\(raw)")

            previous = current
        }
    }

    // MARK: - 字位簇边界

    @Test("不从代理对或 ZWJ 序列中间切开")
    func doesNotSplitComposedSequence() {
        // "👨‍👩" 与 "👨‍👦"：UTF-16 前 5 个单元相同，第 6 个才发散，
        // 而第 5 个单元是 👩/👦 的高位代理——从那里切开会产生乱码。
        let old = string("a👨‍👩")
        let new = string("a👨‍👦")
        let stable = AttributedPrefix.stableLength(old, new)

        #expect(stable < 5, "不能停在代理对内部")
        #expect(isCharacterBoundary(old.string, stable))
        #expect(isCharacterBoundary(new.string, stable))
    }

    @Test("emoji 纯追加时前缀仍是整个旧串")
    func appendAfterEmoji() {
        let old = string("好的👨‍👩‍👧")
        let new = string("好的👨‍👩‍👧，没问题")
        let stable = AttributedPrefix.stableLength(old, new)
        #expect(stable == old.length)
        #expect(isCharacterBoundary(old.string, stable))
    }

    @Test("中文与 emoji 混排逐字追加都落在字位簇边界上")
    func boundaryHoldsForMixedContent() {
        let full = "进度 50%👍 已完成，下一步见👨‍💻 文档"
        var previous = NSAttributedString()
        for length in 1...full.count {
            let current = string(String(full.prefix(length)))
            let stable = AttributedPrefix.stableLength(previous, current)
            #expect(isCharacterBoundary(current.string, stable),
                    "偏移 \(stable) 落在字位簇内部：\(current.string)")
            previous = current
        }
    }
}
