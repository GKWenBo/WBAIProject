import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("代码高亮")
struct CodeHighlighterTests {

    private let highlighter = CodeHighlighter()
    private let theme = MarkdownTheme.default

    /// 取出指定子串被标记的 token 类型
    private func kind(of substring: String, in code: String, language: String?) -> CodeTokenKind? {
        let attributed = highlighter.highlight(code: code, language: language, theme: theme)
        guard let range = code.range(of: substring) else { return nil }
        let location = code.distance(from: code.startIndex, to: range.lowerBound)
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
}
