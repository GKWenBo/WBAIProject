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

    @Test("prepareForReuse 清空文本内容")
    func prepareForReuseClearsContent() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "有内容"))
        view.prepareForReuse()
        #expect(view.currentTextForTesting.isEmpty)
    }

    // MARK: - Important 1：viewKind 单一事实来源

    @Test("三个块视图实现类各自声明 viewKind")
    func viewKindsAreDeclaredCorrectly() {
        #expect(MarkdownTextBlockView.viewKind == .text)
        #expect(CodeBlockView.viewKind == .code)
        #expect(DividerBlockView.viewKind == .divider)
    }

    @Test("recycle 依据 viewKind 归类，dequeue 拿回同类型实例")
    func recycleThenDequeueReturnsSameType() {
        let pool = BlockViewPool()
        let divider = pool.dequeue(.divider)
        pool.recycle(divider)
        let dequeued = pool.dequeue(.divider)
        #expect(dequeued is DividerBlockView)

        let code = pool.dequeue(.code)
        pool.recycle(code)
        #expect(pool.dequeue(.code) is CodeBlockView)
    }

    // MARK: - Minor 5：分割线视图的复用路径

    @Test("复用池不会把分割线视图当成文本块发出")
    func poolKeepsDividerKindSeparate() {
        let pool = BlockViewPool()
        let divider = pool.dequeue(.divider)
        pool.recycle(divider)
        let text = pool.dequeue(.text)
        #expect(text is MarkdownTextBlockView)
        #expect(divider is DividerBlockView)
    }

    // MARK: - Important 2：链接点击需命中字符实际矩形

    @Test("点击链接文字位置触发 onLinkTap 且 URL 正确")
    func linkTapTriggersCallbackWithCorrectURL() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "[点我](https://example.com)"))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: max(1, view.heightThatFits(width: 300)))
        view.layoutIfNeeded()

        var tapped: URL?
        view.onLinkTap = { tapped = $0 }
        view.simulateTapForTesting(at: CGPoint(x: 5, y: view.frame.height / 2))
        #expect(tapped == URL(string: "https://example.com"))
    }

    @Test("点击远离文本的空白区域不触发 onLinkTap")
    func blankAreaTapDoesNotTriggerCallback() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "[点我](https://example.com)"))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: max(1, view.heightThatFits(width: 300)))
        view.layoutIfNeeded()

        var tapped: URL?
        view.onLinkTap = { tapped = $0 }
        view.simulateTapForTesting(at: CGPoint(x: 5, y: 5000))
        #expect(tapped == nil)
    }

    @Test("点击换行后的行间空白不触发 onLinkTap")
    func wrappedLineGapTapDoesNotTriggerCallback() {
        let view = MarkdownTextBlockView()
        // 足够长的链接文字，会在 300pt 宽度下换行成多行
        let text = "[click here for the extended detailed article about many various different topics today](https://example.com)"
        configure(view, block(.paragraph, text))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: max(1, view.heightThatFits(width: 300)))
        view.layoutIfNeeded()

        var tapped: URL?
        view.onLinkTap = { tapped = $0 }
        // (290, 10) 落在第一行的行高范围内、右侧空白处：closestPosition 会把它归到
        // 第二行行首（仍在同一个链接的字符范围内），但那个字符的实际矩形在第二行，
        // 并不覆盖第一行的这次点击——没有 firstRect 校验就会被误判为命中链接。
        view.simulateTapForTesting(at: CGPoint(x: 290, y: 10))
        #expect(tapped == nil)
    }

    @Test("链接为块尾内容时点击最后一个字符右半侧仍触发 onLinkTap")
    func linkAtEndOfDocumentRightEdgeTriggersCallback() {
        let view = MarkdownTextBlockView()
        configure(view, block(.paragraph, "详见[文档](https://example.com)"))
        view.frame = CGRect(x: 0, y: 0, width: 300, height: max(1, view.heightThatFits(width: 300)))
        view.layoutIfNeeded()

        // 取最后一个字符矩形的右半侧：closestPosition(to:) 在此处会返回
        // endOfDocument（离文末最近），验证的正是这种边界情况。
        let rect = view.lastCharacterRectForTesting()
        let point = CGPoint(x: rect.maxX - 1, y: rect.midY)

        var tapped: URL?
        view.onLinkTap = { tapped = $0 }
        view.simulateTapForTesting(at: point)
        #expect(tapped == URL(string: "https://example.com"))
    }

    // MARK: - Important 3：prepareForReuse 需要更强的判别力

    @Test("prepareForReuse 复位引用块的竖条、缩进与点击回调")
    func prepareForReuseResetsQuoteStateAndCallback() {
        let view = MarkdownTextBlockView()
        configure(view, block(.blockQuote, "引用内容"))
        view.onLinkTap = { _ in }

        view.prepareForReuse()

        #expect(view.currentTextForTesting.isEmpty)
        #expect(view.quoteBarHiddenForTesting)
        #expect(view.leadingConstantForTesting == 0)
        #expect(view.onLinkTap == nil)
    }

    @Test("代码块 prepareForReuse 复位代码、语言标签与横向滚动位置")
    func codeBlockPrepareForReuseResetsState() {
        let view = CodeBlockView()
        configure(view, block(.codeFence(language: "swift"),
                              "```swift\n" + String(repeating: "let a = 1; ", count: 40) + "\n```"))
        view.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        view.layoutIfNeeded()
        view.contentOffsetForTesting = CGPoint(x: 50, y: 0)

        view.prepareForReuse()

        #expect(view.codeForTesting.isEmpty)
        #expect(view.languageText.isEmpty)
        #expect(view.contentOffsetForTesting == .zero)
    }
}
