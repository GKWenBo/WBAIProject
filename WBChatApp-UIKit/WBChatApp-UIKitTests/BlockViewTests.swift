import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("块视图")
@MainActor
struct BlockViewTests {

    private let renderer = AttributedRenderer()

    private func block(_ kind: MarkdownBlockKind, _ text: String,
                       sealed: Bool = true) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: kind, rawText: text, isSealed: sealed)
    }

    private func configure(_ view: any BlockView, _ block: MarkdownBlock) {
        view.configure(block: block, attributed: renderer.render(block), renderer: renderer)
    }

    @Test("文本块视图始终使用 TextKit 2")
    func textBlockUsesTextKit2() {
        let view = MarkdownTextBlockView()
        #expect(view.usesTextKit2)
    }

    @Test("文本块高度随内容增长")
    func textHeightGrowsWithContent() {
        let short = MarkdownTextBlockView()
        configure(short, block(.paragraph, "短"))
        let long = MarkdownTextBlockView()
        configure(long, block(.paragraph, String(repeating: "很长的一段文字。", count: 40)))
        #expect(long.heightThatFits(width: 300) > short.heightThatFits(width: 300))
    }

    @Test("同内容同宽度高度稳定")
    func textHeightIsStable() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "稳定的内容"))
        #expect(view.heightThatFits(width: 300) == view.heightThatFits(width: 300))
    }

    @Test("宽度变窄高度变高")
    func narrowerWidthMeansTallerHeight() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, String(repeating: "文字", count: 60)))
        #expect(view.heightThatFits(width: 150) > view.heightThatFits(width: 350))
    }

    @Test("代码块展示语言标签")
    func codeBlockShowsLanguage() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: "swift"), "```swift\nlet a = 1\n```"))
        #expect(view.languageText == "swift")
    }

    @Test("无语言时标签为纯文本")
    func codeBlockWithoutLanguage() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: nil), "```\nplain\n```"))
        #expect(view.languageText == "纯文本")
    }

    @Test("代码块复制回调带出剥掉围栏的代码")
    func codeBlockCopyCallback() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: "swift"), "```swift\nlet a = 1\n```"))
        var copied: String?
        view.onCopy = { copied = $0 }
        view.triggerCopyForTesting()
        #expect(copied == "let a = 1")
    }

    @Test("复用池按类型回收与复用同一实例")
    func poolReusesSameInstance() {
        let pool = BlockViewPool()
        let first = pool.dequeue(.text)
        pool.recycle(first)
        let second = pool.dequeue(.text)
        #expect(first === second)
    }

    @Test("复用池不会把代码块视图当成文本块发出")
    func poolKeepsKindsSeparate() {
        let pool = BlockViewPool()
        let code = pool.dequeue(.code)
        pool.recycle(code)
        let text = pool.dequeue(.text)
        #expect(text is MarkdownTextBlockView)
        #expect(code is CodeBlockView)
    }

    @Test("块类型到视图类型的映射")
    func kindMapping() {
        #expect(BlockViewKind.kind(for: .paragraph) == .text)
        #expect(BlockViewKind.kind(for: .heading(level: 2)) == .text)
        #expect(BlockViewKind.kind(for: .list(ordered: true)) == .text)
        #expect(BlockViewKind.kind(for: .blockQuote) == .text)
        #expect(BlockViewKind.kind(for: .table) == .text)
        #expect(BlockViewKind.kind(for: .codeFence(language: nil)) == .code)
        #expect(BlockViewKind.kind(for: .thematicBreak) == .divider)
    }

    @Test("分割线高度固定")
    func dividerHasFixedHeight() {
        let view = DividerBlockView()
        configure(view, block(.thematicBreak, "---"))
        #expect(view.heightThatFits(width: 300) == view.heightThatFits(width: 100))
    }

    @Test("prepareForReuse 清空内容")
    func prepareForReuseClearsContent() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "有内容"))
        view.prepareForReuse()
        #expect(view.currentTextForTesting.isEmpty)
    }
}
