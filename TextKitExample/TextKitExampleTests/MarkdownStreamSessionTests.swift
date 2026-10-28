//
//  MarkdownStreamSessionTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

@Suite("Markdown 切块")
struct MarkdownBlockSplitterTests {

    @Test("没有空行时整段都是尾块")
    func noBlankLine() {
        #expect(MarkdownBlockSplitter.tailStart(in: "") == 0)
        #expect(MarkdownBlockSplitter.tailStart(in: "第一段") == 0)
        #expect(MarkdownBlockSplitter.tailStart(in: "第一段\n第二行") == 0)
    }

    @Test("空行之后才是尾块，边界是空行末尾的偏移")
    func blankLineClosesBlock() {
        let source = "第一段\n\n第二段"
        #expect(MarkdownBlockSplitter.tailStart(in: source) == ("第一段\n\n" as NSString).length)
    }

    @Test("空行还没写完整（只有一个换行）时，前一块不算闭合")
    func incompleteBlankLine() {
        #expect(MarkdownBlockSplitter.tailStart(in: "第一段\n") == 0)
    }

    @Test("围栏代码块里的空行不是边界")
    func blankLineInsideFence() {
        let open = "前言\n\n```swift\nlet a = 1\n\nlet b = 2\n"
        #expect(MarkdownBlockSplitter.tailStart(in: open) == ("前言\n\n" as NSString).length)

        // 围栏闭合并且后面出现空行之后，整个代码块才闭合。
        let closed = open + "```\n\n后文"
        #expect(MarkdownBlockSplitter.tailStart(in: closed) == (open + "```\n\n" as NSString).length)
    }

    @Test("偏移按 UTF-16 计算，emoji 不会错位")
    func utf16Offsets() {
        let source = "你好 👌\n\n尾"
        #expect(MarkdownBlockSplitter.tailStart(in: source) == ("你好 👌\n\n" as NSString).length)
    }
}

@MainActor
@Suite("Markdown 流式会话")
struct MarkdownStreamSessionTests {

    private func makeRenderer() -> TextKit2IncrementalRenderer {
        let renderer = TextKit2IncrementalRenderer()
        renderer.textContainer.size = CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude)
        return renderer
    }

    /// 按固定节奏把原文切成小块喂给会话。
    private func stream(_ text: String, into session: MarkdownStreamSession) -> [IncrementalUpdateReport] {
        var source = StreamingTextSource(text: text)
        var reports: [IncrementalUpdateReport] = []
        while let chunk = source.next() {
            reports.append(session.append(chunk))
        }
        return reports
    }

    @Test("逐块增量渲染的结果，与一次性渲染全文逐字符、逐属性一致")
    func streamingEqualsOneShot() throws {
        let renderer = makeRenderer()
        let session = MarkdownStreamSession(renderer: renderer)
        _ = stream(SampleText.streamingMarkdown, into: session)

        let storage = try #require(renderer.contentStorage.textStorage)
        let expected = MarkdownRenderer.render(SampleText.streamingMarkdown)
        #expect(storage.string == expected.string)
        #expect(storage.isEqual(to: expected))
    }

    @Test("语法标记被吃掉：标题、粗体、围栏都不会出现在结果里")
    func markersAreConsumed() {
        let renderer = makeRenderer()
        let session = MarkdownStreamSession(renderer: renderer)
        _ = stream(SampleText.streamingMarkdown, into: session)

        #expect(!renderer.string.contains("##"))
        // 原文里行内代码 `**加粗` 会合法地保留 `**`，所以只检查真正的粗体标记。
        #expect(!renderer.string.contains("**前面"))
        #expect(!renderer.string.contains("```"))
        #expect(renderer.string.contains("• 用空行切块"))
    }

    @Test("半截的 ** 立刻就是粗体，不会先显示原样再跳变")
    func unclosedBoldIsAlreadyBold() throws {
        let renderer = makeRenderer()
        let session = MarkdownStreamSession(renderer: renderer)
        _ = session.append("前缀 **加粗")

        let storage = try #require(renderer.contentStorage.textStorage)
        #expect(storage.string == "前缀 加粗")
        let font = try #require(storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as? UIFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("块闭合之后，之前的内容不再参与重排")
    func frozenBlocksAreNotRelaid() throws {
        let renderer = makeRenderer()
        let session = MarkdownStreamSession(renderer: renderer)
        _ = session.append("第一段内容比较长，用来占一些字符。\n\n第二段开始")
        let report = session.append("了")

        // 只重排尾块那一段，字符数远小于全文。
        #expect(report.relaidUnits == 1)
        #expect(report.relaidCharacters < report.totalLength)
    }

    @Test("reset 之后可以重新开始，偏移不会残留")
    func resetClearsOffsets() {
        let renderer = makeRenderer()
        let session = MarkdownStreamSession(renderer: renderer)
        _ = stream(SampleText.streamingMarkdown, into: session)
        session.reset()
        #expect(renderer.string.isEmpty)

        _ = session.append("新的一段\n\n尾")
        // 空行不输出，每个原文行渲染成一个以 "\n" 结尾的段落。
        #expect(renderer.string == "新的一段\n尾")
    }
}
