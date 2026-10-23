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

    // MARK: - 增量扫描的安全切点

    private func cleanCut(_ code: String, language: String?) -> Int {
        highlighter.scan(code: code, language: language, theme: theme).cleanCutCharacterCount
    }

    @Test("highlight 与 scan 产出同一个属性串")
    func highlightMatchesScan() {
        let code = "func greet() {\n    print(\"hi\")\n}"
        let viaHighlight = highlighter.highlight(code: code, language: "swift", theme: theme)
        let viaScan = highlighter.scan(code: code, language: "swift", theme: theme).attributed
        #expect(viaHighlight.isEqual(to: viaScan))
    }

    @Test("安全切点落在行首")
    func cleanCutIsAtLineStart() {
        let code = "let a = 1\nlet b = 2\nlet c = 3"
        let cut = cleanCut(code, language: "swift")
        #expect(cut > 0)
        let prefix = String(code.prefix(cut))
        #expect(prefix.hasSuffix("\n"))
    }

    @Test("未闭合的块注释内部不产生安全切点")
    func noCleanCutInsideUnterminatedBlockComment() {
        let code = "let a = 1\n/* 注释开始\n还在注释里\n继续"
        let cut = cleanCut(code, language: "swift")
        // 只能切在块注释开始之前
        #expect(cut <= "let a = 1\n".count)
    }

    @Test("跨行块注释内部不产生安全切点")
    func noCleanCutInsideBlockComment() {
        let code = "/* 第一行\n第二行\n第三行 */ let a = 1"
        // 第 2、3 行的行首都在注释内部，整段没有安全切点
        #expect(cleanCut(code, language: "swift") == 0)
    }

    @Test("反斜杠续行的字符串内部不产生安全切点")
    func noCleanCutInsideContinuedString() {
        // 行尾反斜杠会让扫描器跨过换行继续把下一行当成字符串
        let code = "let a = \"开头\\\n继续\\\n结尾\""
        #expect(cleanCut(code, language: "swift") == 0)
    }

    // MARK: - 增量等价性（合并闸门）

    /// 逐步喂入递增前缀，每一步都必须与「全新实例一次性渲染」的结果完全相同。
    /// 这条测试守的是 `AttributedCache` 要求的纯函数契约：增量记忆不得让
    /// 同一段代码因为喂入历史不同而产出不同的属性串。
    private func expectIncrementalEqualsFull(_ code: String, language: String?,
                                             step: Int, sourceLocation: SourceLocation = #_sourceLocation) {
        let shared = AttributedRenderer()
        var length = step
        while length < code.count {
            let partial = String(code.prefix(length))
            let raw = "```\(language ?? "")\n\(partial)"
            let block = MarkdownBlock(ordinal: 0, kind: .codeFence(language: language),
                                      rawText: raw, isSealed: false)
            let incremental = shared.render(block)
            let fresh = AttributedRenderer().render(block)
            #expect(incremental.isEqual(to: fresh),
                    "前 \(length) 个字符处增量与全量结果不一致",
                    sourceLocation: sourceLocation)
            length += step
        }
    }

    @Test("增量等价：普通 Swift 代码", arguments: [1, 3, 7])
    func incrementalEqualsFullForSwift(step: Int) {
        expectIncrementalEqualsFull("""
        func greet(name: String) -> String {
            let greeting = "你好，\\(name)"
            // 返回问候语
            return greeting
        }
        """, language: "swift", step: step)
    }

    @Test("增量等价：未闭合与闭合的块注释", arguments: [1, 5])
    func incrementalEqualsFullForBlockComment(step: Int) {
        expectIncrementalEqualsFull("""
        let a = 1
        /* 这是一段
           跨行的注释 */
        let b = 2
        /* 又开一个没有关
        """, language: "swift", step: step)
    }

    @Test("增量等价：反斜杠续行字符串", arguments: [1, 4])
    func incrementalEqualsFullForContinuedString(step: Int) {
        expectIncrementalEqualsFull("""
        let s = "第一段\\
        第二段\\
        第三段"
        let t = 2
        """, language: "swift", step: step)
    }

    @Test("增量等价：含 emoji 与中文的代码", arguments: [1, 2])
    func incrementalEqualsFullWithEmoji(step: Int) {
        expectIncrementalEqualsFull("""
        let 状态 = "运行中 🚀"
        // 进度 👨‍💻 100%
        print(状态)
        """, language: "swift", step: step)
    }

    @Test("增量等价：Python 与 Bash 的 # 注释", arguments: [1, 6])
    func incrementalEqualsFullForHashComment(step: Int) {
        expectIncrementalEqualsFull("""
        # 注释一行
        def greet(name):
            return f"hi {name}"  # 行尾注释
        """, language: "python", step: step)

        expectIncrementalEqualsFull("""
        # 构建脚本
        for f in *.swift; do
            echo "$f"
        done
        """, language: "bash", step: step)
    }

    @Test("增量等价：CRLF 换行")
    func incrementalEqualsFullForCRLF() {
        expectIncrementalEqualsFull("let a = 1\r\nlet b = 2\r\n// 注释\r\nlet c = 3",
                                    language: "swift", step: 1)
    }

    @Test("增量等价：Objective-C 的 @ 标识符")
    func incrementalEqualsFullForObjC() {
        expectIncrementalEqualsFull("""
        @interface Foo : NSObject
        @property (nonatomic) NSInteger count;
        @end
        """, language: "objc", step: 2)
    }

    @Test("切换语言后记忆作废，不会串用上一种语言的高亮")
    func switchingLanguageInvalidatesMemo() {
        let renderer = AttributedRenderer()
        let swiftBlock = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "swift"),
                                       rawText: "```swift\nfunc a() {}\n", isSealed: false)
        _ = renderer.render(swiftBlock)

        // 同样的代码文本，换成 python：func 不再是关键字
        let pythonBlock = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "python"),
                                        rawText: "```python\nfunc a() {}\n", isSealed: false)
        let incremental = renderer.render(pythonBlock)
        let fresh = AttributedRenderer().render(pythonBlock)
        #expect(incremental.isEqual(to: fresh))
    }
}
