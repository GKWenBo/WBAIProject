import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("块容器")
@MainActor
struct BlockStackViewTests {

    private func makeStack() -> BlockStackView {
        BlockStackView(pool: BlockViewPool(),
                       cache: AttributedCache(),
                       renderer: AttributedRenderer())
    }

    private func sealed(_ ordinal: Int, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: true)
    }

    private func open(_ ordinal: Int, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: false)
    }

    @Test("setBlocks 建出对应数量的子视图")
    func setBlocksCreatesSubviews() {
        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, "乙")])
        #expect(stack.blockCount == 2)
    }

    @Test("补丁只新增已闭合块与一个未闭合块")
    func patchAppendsBlocks() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "甲")], open: open(1, "乙")))
        #expect(stack.blockCount == 2)
    }

    @Test("连续补丁只替换未闭合块，不重复追加")
    func repeatedOpenPatchReplacesInPlace() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写到")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "写到一半")))
        #expect(stack.blockCount == 1)
    }

    @Test("已闭合块的视图实例在后续补丁中保持不变")
    func sealedBlockViewIdentityIsStable() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "固定")], open: open(1, "变")))
        let firstView = stack.blockViewForTesting(at: 0)

        stack.applyPatch(BlockPatch(newlySealed: [], open: open(1, "变化中")))
        stack.applyPatch(BlockPatch(newlySealed: [sealed(1, "变化完")], open: open(2, "新")))

        #expect(stack.blockViewForTesting(at: 0) === firstView,
                "已闭合块的视图被重建了，增量渲染的收益作废")
    }

    @Test("未闭合块转为已闭合时复用同一个视图实例")
    func openBlockBecomesSealedInPlace() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "半成品")))
        let view = stack.blockViewForTesting(at: 0)
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "成品")], open: nil))
        #expect(stack.blockViewForTesting(at: 0) === view)
        #expect(stack.blockCount == 1)
    }

    @Test("open 为 nil 时移除未闭合块视图")
    func nilOpenRemovesTrailingView() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [sealed(0, "甲")], open: open(1, "乙")))
        stack.applyPatch(BlockPatch(newlySealed: [], open: nil))
        #expect(stack.blockCount == 1)
    }

    @Test("块类型变化时换用对应的视图类型")
    func kindChangeSwapsViewType() {
        let stack = makeStack()
        stack.applyPatch(BlockPatch(newlySealed: [], open: open(0, "普通段落")))
        #expect(stack.blockViewForTesting(at: 0) is MarkdownTextBlockView)

        let codeBlock = MarkdownBlock(ordinal: 0, kind: .codeFence(language: "swift"),
                                      rawText: "```swift\nlet a = 1", isSealed: false)
        stack.applyPatch(BlockPatch(newlySealed: [], open: codeBlock))
        #expect(stack.blockViewForTesting(at: 0) is CodeBlockView)
    }

    @Test("总高度等于各块高度与间距之和")
    func heightIsSumOfBlocks() {
        // 两块刻意用不等长的文本：若实现漏加 spacing，或者用「块数 * 单块高度」
        // 之类的近似算法，等长文本测不出来，这里用「总高 = 各块单独高度之和 +
        // 间距 × (块数 - 1)」的精确等式来校验。
        let longText = "这是一段更长一些的文字，用来确保两个块的单独高度不同，从而使求和断言更有区分度。"

        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, longText)])
        let total = stack.heightThatFits(width: 300)

        let first = makeStack()
        first.setBlocks([sealed(0, "甲")])
        let firstHeight = first.heightThatFits(width: 300)

        let second = makeStack()
        second.setBlocks([sealed(1, longText)])
        let secondHeight = second.heightThatFits(width: 300)

        let spacing = MarkdownTheme.default.blockSpacing
        #expect(total == firstHeight + secondHeight + spacing,
                "总高度应精确等于两块各自高度之和加一份间距")
    }

    @Test("recycleAll 清空所有子视图")
    func recycleAllClears() {
        let stack = makeStack()
        stack.setBlocks([sealed(0, "甲"), sealed(1, "乙")])
        stack.recycleAll()
        #expect(stack.blockCount == 0)
    }

    @Test("助手 cell 转发补丁并能报高度")
    func assistantCellAppliesPatch() {
        let cell = AssistantMessageCell(style: .default, reuseIdentifier: AssistantMessageCell.reuseIdentifier)
        cell.configure(blocks: [sealed(0, "你好")],
                       reasoning: nil,
                       status: .completed,
                       errorText: nil,
                       pool: BlockViewPool(),
                       cache: AttributedCache(),
                       renderer: AttributedRenderer())
        #expect(cell.blockCountForTesting == 1)
        let heightBefore = cell.heightThatFits(width: 375)

        // 断言的核心不是「高度 > 0」（configure 一个块之后本来就恒为正），而是
        // applyPatch 确实把补丁转发给了容器：块数应该增加，高度也应该随之变大。
        // 若 applyPatch 被改成空实现，这两个断言都会失败。
        cell.applyPatch(BlockPatch(newlySealed: [sealed(1, "补充")], open: nil))

        #expect(cell.blockCountForTesting == 2, "补丁应转发到容器，新增一个已闭合块")
        let heightAfter = cell.heightThatFits(width: 375)
        #expect(heightAfter > heightBefore, "新增块后高度应变大")
    }

    @Test("用户 cell 展示原始文本，不做 Markdown 渲染")
    func userCellShowsPlainText() {
        let cell = UserMessageCell(style: .default, reuseIdentifier: UserMessageCell.reuseIdentifier)
        cell.configure(text: "**不该被加粗**")
        #expect(cell.displayedTextForTesting == "**不该被加粗**")
    }
}
