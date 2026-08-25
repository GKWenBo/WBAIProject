import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("属性串渲染")
struct AttributedRendererTests {

    private let renderer = AttributedRenderer()
    private let theme = MarkdownTheme.default

    private func block(_ kind: MarkdownBlockKind, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: kind, rawText: text, isSealed: true)
    }

    private func traits(_ attributed: NSAttributedString, at index: Int) -> UIFontDescriptor.SymbolicTraits {
        let font = attributed.attribute(.font, at: index, effectiveRange: nil) as? UIFont
        return font?.fontDescriptor.symbolicTraits ?? []
    }

    @Test("段落纯文本")
    func paragraph() {
        let result = renderer.render(block(.paragraph, "普通文本"))
        #expect(result.string == "普通文本")
    }

    @Test("加粗与斜体带上对应 trait")
    func emphasis() {
        let result = renderer.render(block(.paragraph, "前**粗**中*斜*后"))
        #expect(result.string == "前粗中斜后")
        #expect(traits(result, at: 1).contains(.traitBold))
        #expect(traits(result, at: 3).contains(.traitItalic))
        #expect(!traits(result, at: 0).contains(.traitBold))
    }

    @Test("行内代码使用等宽字体")
    func inlineCode() {
        let result = renderer.render(block(.paragraph, "看 `code` 这里"))
        #expect(result.string == "看 code 这里")
        let font = result.attribute(.font, at: 2, effectiveRange: nil) as? UIFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.traitMonoSpace) == true)
    }

    @Test("删除线")
    func strikethrough() {
        let result = renderer.render(block(.paragraph, "~~删掉~~"))
        #expect(result.string == "删掉")
        #expect(result.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) != nil)
    }

    @Test("链接带上 URL 与链接色")
    func link() {
        let result = renderer.render(block(.paragraph, "点[这里](https://example.com)看"))
        #expect(result.string == "点这里看")
        let url = result.attribute(.wbLinkURL, at: 1, effectiveRange: nil) as? URL
        #expect(url == URL(string: "https://example.com"))
        let color = result.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? UIColor
        #expect(color == theme.linkColor)
    }

    @Test("标题使用对应层级字体")
    func heading() {
        let result = renderer.render(block(.heading(level: 1), "# 大标题"))
        #expect(result.string == "大标题")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.headingFont(level: 1))
    }

    @Test("无序列表逐项加项目符号")
    func unorderedList() {
        let result = renderer.render(block(.list(ordered: false), "- 甲\n- 乙"))
        #expect(result.string.contains("• 甲"))
        #expect(result.string.contains("• 乙"))
    }

    @Test("有序列表按序号编号")
    func orderedList() {
        let result = renderer.render(block(.list(ordered: true), "1. 甲\n2. 乙"))
        #expect(result.string.contains("1. 甲"))
        #expect(result.string.contains("2. 乙"))
    }

    @Test("引用块去掉引号前缀并用次要色")
    func blockQuote() {
        let result = renderer.render(block(.blockQuote, "> 引用内容"))
        #expect(result.string == "引用内容")
        let color = result.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(color == theme.secondaryColor)
    }

    @Test("代码块走高亮器，保留原始代码文本")
    func codeFence() {
        let raw = "```swift\nlet a = 1\n```"
        let result = renderer.render(block(.codeFence(language: "swift"), raw))
        #expect(result.string == "let a = 1")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font == theme.monoFont)
    }

    @Test("codeText 剥掉围栏，供复制按钮使用")
    func codeTextStripsFence() {
        let raw = "```swift\nlet a = 1\nlet b = 2\n```"
        let block = block(.codeFence(language: "swift"), raw)
        #expect(renderer.codeText(of: block) == "let a = 1\nlet b = 2")
    }

    @Test("未闭合的代码块也能渲染出已有内容")
    func unclosedCodeFence() {
        let raw = "```swift\nlet a = 1"
        let unsealed = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "swift"),
                                     rawText: raw, isSealed: false)
        #expect(renderer.codeText(of: unsealed) == "let a = 1")
    }

    @Test("同一块渲染两次结果一致（渲染是纯函数）")
    func renderIsDeterministic() {
        let target = block(.paragraph, "**稳定** 的输出")
        #expect(renderer.render(target).isEqual(to: renderer.render(target)))
    }

    // MARK: - 回归：列表项内多个子块不应粘连

    @Test("嵌套列表：子列表与父项文字之间要有换行，不能粘连")
    func nestedListDoesNotGlueChildren() {
        // 实测 swift-markdown 解析 "- 甲\n  - 乙" 得到：
        // Document > UnorderedList > ListItem { Paragraph("甲"), UnorderedList > ListItem { Paragraph("乙") } }
        // 即一个 ListItem 有两个子块：段落 "甲" 和嵌套的无序列表。
        let result = renderer.render(block(.list(ordered: false), "- 甲\n  - 乙"))
        #expect(result.string == "• 甲\n• 乙")
        #expect(!result.string.contains("甲• 乙"))
    }

    @Test("多段落列表项：段落之间要有换行，不能粘连")
    func multiParagraphListItemDoesNotGlueChildren() {
        // 实测 swift-markdown 解析 "- 甲\n\n  乙" 得到：
        // Document > UnorderedList > ListItem { Paragraph("甲"), Paragraph("乙") }
        // 即一个 ListItem 有两个段落子块。
        let result = renderer.render(block(.list(ordered: false), "- 甲\n\n  乙"))
        #expect(result.string == "• 甲\n乙")
        #expect(!result.string.contains("甲乙"))
    }

    // MARK: - 回归护栏（现有实现已经正确，补测试防止未来改坏）

    @Test("只有开围栏、还没换行的代码块不崩溃")
    func codeFenceWithOnlyOpeningLine() {
        let unsealed = block(.codeFence(language: nil), "```")
        #expect(renderer.codeText(of: unsealed) == "")
    }

    @Test("粗斜体嵌套同时带上 bold 与 italic trait")
    func boldItalicNested() {
        let result = renderer.render(block(.paragraph, "***粗斜体***"))
        #expect(result.string == "粗斜体")
        let traits = traits(result, at: 0)
        #expect(traits.contains(.traitBold))
        #expect(traits.contains(.traitItalic))
    }
}
