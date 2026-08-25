import Foundation
import Testing
@testable import WBChatApp_UIKit

@Suite("增量切块状态机")
struct StreamingBlockSplitterTests {

    /// 一次性喂完整文本并收尾，返回全部块
    private func splitAtOnce(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append(text)
        _ = splitter.finish()
        return splitter.allBlocks
    }

    /// 逐字符喂入并收尾，返回全部块
    private func splitCharByChar(_ text: String) -> [MarkdownBlock] {
        var splitter = StreamingBlockSplitter()
        for character in text { _ = splitter.append(String(character)) }
        _ = splitter.finish()
        return splitter.allBlocks
    }

    // MARK: - 块类型识别

    @Test("空行分隔的两个段落")
    func twoParagraphs() {
        let blocks = splitAtOnce("第一段\n\n第二段\n")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(blocks.map(\.rawText) == ["第一段", "第二段"])
    }

    @Test("标题单行成块并立即闭合")
    func heading() {
        let blocks = splitAtOnce("# 大标题\n正文\n")
        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
        #expect(blocks[0].isSealed)
    }

    @Test("围栏代码块内部的空行不切断块")
    func codeFenceKeepsBlankLines() {
        let text = "```swift\nlet a = 1\n\nlet b = 2\n```\n"
        let blocks = splitAtOnce(text)
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeFence(language: "swift"))
        #expect(blocks[0].rawText.contains("let b = 2"))
    }

    @Test("代码块内的 # 与 - 不会被误判成标题或列表")
    func codeFenceSwallowsMarkers() {
        let blocks = splitAtOnce("```\n# 这是注释\n- 这是短横线\n```\n")
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .codeFence(language: nil))
    }

    @Test("未闭合的代码块保持 open 且可见")
    func unclosedCodeFenceStaysOpen() {
        var splitter = StreamingBlockSplitter()
        let patch = splitter.append("```swift\nlet a = 1\n")
        #expect(patch.newlySealed.isEmpty)
        let open = try! #require(patch.open)
        #expect(open.kind == .codeFence(language: "swift"))
        #expect(open.isSealed == false)
        #expect(open.rawText.contains("let a = 1"))
    }

    @Test("无序与有序列表")
    func lists() {
        let blocks = splitAtOnce("- a\n- b\n\n1. x\n2. y\n\n")
        #expect(blocks.map(\.kind) == [.list(ordered: false), .list(ordered: true)])
    }

    @Test("列表项之间的单个空行不切断列表")
    func looseList() {
        let blocks = splitAtOnce("- a\n\n- b\n\n正文\n")
        #expect(blocks.map(\.kind) == [.list(ordered: false), .paragraph])
        #expect(blocks[0].rawText.contains("- b"))
    }

    @Test("引用块")
    func blockQuote() {
        let blocks = splitAtOnce("> 引用一\n> 引用二\n正文\n")
        #expect(blocks.map(\.kind) == [.blockQuote, .paragraph])
    }

    @Test("表格")
    func table() {
        let blocks = splitAtOnce("| a | b |\n| --- | --- |\n| 1 | 2 |\n\n尾巴\n")
        #expect(blocks.map(\.kind) == [.table, .paragraph])
    }

    @Test("分割线不被当成列表")
    func thematicBreak() {
        let blocks = splitAtOnce("上\n\n---\n\n下\n")
        #expect(blocks.map(\.kind) == [.paragraph, .thematicBreak, .paragraph])
    }

    @Test("段落后紧跟标题不需要空行也能切开")
    func paragraphThenHeadingWithoutBlankLine() {
        let blocks = splitAtOnce("正文\n## 小标题\n")
        #expect(blocks.map(\.kind) == [.paragraph, .heading(level: 2)])
    }

    // MARK: - 核心不变量

    @Test("核心不变量：已闭合块序列只增不改")
    func sealedBlocksAreMonotonic() {
        let document = """
        # 标题

        这是一段正文，包含 **加粗** 和 `代码`。

        - 列表一
        - 列表二

        ```swift
        let x = 1
        ```

        > 引用

        | a | b |
        | --- | --- |
        | 1 | 2 |

        ---

        收尾段落。
        """

        var splitter = StreamingBlockSplitter()
        var previousSealed: [MarkdownBlock] = []

        for character in document {
            _ = splitter.append(String(character))
            let current = splitter.sealedBlocks

            // 1. 数量只增不减
            #expect(current.count >= previousSealed.count)
            // 2. 已有的每一个块内容完全不变
            for index in previousSealed.indices {
                #expect(current[index] == previousSealed[index],
                        "第 \(index) 个已闭合块被修改了，不变量被破坏")
            }
            previousSealed = current
        }
    }

    @Test("逐字符喂入与一次性喂入结果完全一致")
    func incrementalEqualsAtOnce() {
        let documents = [
            "# 标题\n\n正文\n",
            "```swift\nlet a = 1\n\nlet b = 2\n```\n\n后续\n",
            "- a\n\n- b\n\n正文\n",
            "> 引用\n\n| a | b |\n| --- | --- |\n\n---\n\n结尾",
            "没有换行结尾的裸段落",
        ]
        for document in documents {
            #expect(splitCharByChar(document) == splitAtOnce(document),
                    "文档不一致：\(document)")
        }
    }

    // MARK: - 换行与收尾

    @Test("CRLF 与 CR 都能正确断行")
    func lineEndings() {
        #expect(splitAtOnce("a\r\n\r\nb\r\n").map(\.rawText) == ["a", "b"])
        #expect(splitAtOnce("a\r\rb\r").map(\.rawText) == ["a", "b"])
    }

    @Test("CRLF 被切在两次 append 之间不会产生空块")
    func crlfSplitAcrossAppends() {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append("a\r")
        _ = splitter.append("\nb\r\n")
        _ = splitter.finish()
        // "a\r" + "\nb\r\n" 是同一个 CRLF 被切在两次 append 之间：
        // 行序列应为 "a"、"b" 两行非空行，属于同一段落（软换行），
        // 合并成一个块 "a\nb"。若被误判为空行分隔的两段（["a", "b"]），
        // 说明 CRLF 被错误拆成了「行终止 + 一个空行」。
        #expect(splitter.allBlocks.map(\.rawText) == ["a\nb"])
    }

    @Test("连续非空行合并为一个段落，软换行不切块")
    func softBreaksStayInOneParagraph() {
        let blocks = splitAtOnce("第一行\n第二行\n第三行\n\n下一段\n")
        #expect(blocks.map(\.kind) == [.paragraph, .paragraph])
        #expect(blocks.map(\.rawText) == ["第一行\n第二行\n第三行", "下一段"])
    }

    @Test("finish 把最后的 open 块闭合")
    func finishSealsOpenBlock() {
        var splitter = StreamingBlockSplitter()
        _ = splitter.append("最后一段没有换行")
        let patch = splitter.finish()
        #expect(patch.open == nil)
        #expect(patch.newlySealed.count == 1)
        #expect(patch.newlySealed[0].isSealed)
        #expect(patch.newlySealed[0].rawText == "最后一段没有换行")
    }

    @Test("ordinal 单调递增且不重复")
    func ordinalsAreMonotonic() {
        let blocks = splitAtOnce("a\n\nb\n\nc\n\n")
        #expect(blocks.map(\.ordinal) == [0, 1, 2])
    }

    @Test("open 块的 ordinal 接在已闭合块之后")
    func openBlockOrdinal() {
        var splitter = StreamingBlockSplitter()
        let patch = splitter.append("a\n\nb")
        #expect(patch.newlySealed.map(\.ordinal) == [0])
        #expect(patch.open?.ordinal == 1)
    }

    @Test("纯空白输入不产生任何块")
    func onlyWhitespace() {
        #expect(splitAtOnce("\n\n   \n\n").isEmpty)
    }

    @Test("cacheKey 对同内容稳定、对不同内容不同")
    func cacheKeyStability() {
        let a = MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: "文本", isSealed: true)
        let b = MarkdownBlock(ordinal: 5, kind: .paragraph, rawText: "文本", isSealed: true)
        let c = MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: "别的", isSealed: true)
        #expect(a.cacheKey == b.cacheKey)   // 与 ordinal 无关
        #expect(a.cacheKey != c.cacheKey)
    }
}
