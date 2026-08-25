import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("代码高亮")
struct CodeHighlighterTests {

    private let highlighter = CodeHighlighter()
    private let theme = MarkdownTheme.default

    /// 取出指定子串被标记的 token 类型
    ///
    /// 注意：`attributed` 底层是 `NSAttributedString`，其 `NSRange` 用的是 UTF-16 偏移，
    /// 而不是 Swift 的 Character（字位簇）偏移。之前这里用 `code.distance(from:to:)`
    /// 算的是 Character 偏移，在含 emoji 等非 BMP 字符的用例上会定位到错误的位置，
    /// 因此改用 `code.utf16.distance(from:to:)`。
    private func kind(of substring: String, in code: String, language: String?) -> CodeTokenKind? {
        let attributed = highlighter.highlight(code: code, language: language, theme: theme)
        guard let range = code.range(of: substring) else { return nil }
        guard let utf16Lower = range.lowerBound.samePosition(in: code.utf16) else { return nil }
        let location = code.utf16.distance(from: code.utf16.startIndex, to: utf16Lower)
        let raw = attributed.attribute(.wbCodeTokenKind, at: location, effectiveRange: nil) as? String
        return raw.flatMap(CodeTokenKind.init(rawValue:))
    }

    @Test("Swift 关键字被标记")
    func swiftKeyword() {
        #expect(kind(of: "func", in: "func greet() {}", language: "swift") == .keyword)
    }

    @Test("字符串字面量被标记")
    func stringLiteral() {
        #expect(kind(of: "\"hi\"", in: "let a = \"hi\"", language: "swift") == .string)
    }

    @Test("行注释被标记")
    func lineComment() {
        #expect(kind(of: "// 说明", in: "let a = 1 // 说明", language: "swift") == .comment)
    }

    @Test("数字被标记")
    func number() {
        #expect(kind(of: "42", in: "let a = 42", language: "swift") == .number)
    }

    @Test("字符串内部的关键字不被误标")
    func keywordInsideStringIsNotHighlighted() {
        #expect(kind(of: "func", in: "let a = \"func\"", language: "swift") == .string)
    }

    @Test("注释内部的关键字不被误标")
    func keywordInsideCommentIsNotHighlighted() {
        #expect(kind(of: "func", in: "// func 只是文字", language: "swift") == .comment)
    }

    @Test("JSON 的键值都按字符串处理")
    func jsonStrings() {
        #expect(kind(of: "\"name\"", in: "{\"name\": \"张三\"}", language: "json") == .string)
    }

    @Test("Python 关键字")
    func pythonKeyword() {
        #expect(kind(of: "def", in: "def main():", language: "python") == .keyword)
    }

    @Test("未知语言降级为通用规则，仍能识别字符串与注释")
    func unknownLanguageFallback() {
        #expect(kind(of: "\"x\"", in: "a = \"x\" // 注释", language: "rust") == .string)
        #expect(kind(of: "// 注释", in: "a = \"x\" // 注释", language: "rust") == .comment)
    }

    @Test("输出长度与输入一致，不丢字符")
    func lengthPreserved() {
        let code = "func f() {\n  return \"x\" // c\n}"
        let attributed = highlighter.highlight(code: code, language: "swift", theme: theme)
        #expect(attributed.string == code)
    }

    @Test("整段使用等宽字体")
    func monospacedFont() {
        let attributed = highlighter.highlight(code: "let a = 1", language: "swift", theme: theme)
        let font = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.monoFont)
    }

    // MARK: - 缺陷 1：字符串以孤立反斜杠结尾时越界崩溃

    @Test("未闭合字符串以孤立反斜杠结尾不应崩溃")
    func unterminatedStringEndingWithLoneBackslashDoesNotCrash() {
        // 流式渲染场景下，代码块在围栏闭合前就可能被截断到「反斜杠恰好是最后一个字符」这种输入。
        let code = "let a = \"x\\"
        let attributed = highlighter.highlight(code: code, language: "swift", theme: theme)
        #expect(attributed.string == code)
    }

    // MARK: - 缺陷 2：Character 偏移与 UTF-16 偏移不一致

    @Test("emoji 之后的 token 仍被正确标记为注释")
    func tokenAfterEmojiIsHighlightedCorrectly() {
        // "🚀" 是非 BMP 字符，占 2 个 UTF-16 code unit 但只有 1 个 Character。
        // 注意：断言点必须选在注释 token 的末尾字符「释」而非整体子串「// 注释」的起始位置——
        // 因为 Character/UTF-16 偏移只错位 1 个单位，用扫描算出的 Character 区间 [12,17)
        // 直接当 NSRange 用时，恰好仍覆盖到子串起始位置 13，会让断言误判通过，抓不到 bug；
        // 但区间末尾少算的那 1 个单位会把最后一个字符「释」漏在外面，用它作为断言点才有判别力。
        let code = "let a = \"🚀\" // 注释"
        #expect(kind(of: "释", in: code, language: "swift") == .comment)
    }

    @Test("含 emoji 的代码输出长度与输入一致")
    func lengthPreservedWithEmoji() {
        let code = "let a = \"🚀\" // 注释"
        let attributed = highlighter.highlight(code: code, language: "swift", theme: theme)
        #expect(attributed.string == code)
    }
}
