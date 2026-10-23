import UIKit
import Testing
@testable import WBChatApp_UIKit

/// 回归测试：离屏测量（`ChatViewController.measureHeight`）曾经每次高度缓存 miss
/// 都新建一个 `AssistantMessageCell`，其内部 `BlockStackView` 借走的是共享的
/// `BlockViewPool`；这个临时 cell 用完即弃，从未调用 `prepareForReuse` /
/// `recycleAll` / `pool.recycle`，借走的块视图永远归还不了池子。
///
/// 修法是让 `ChatViewController` 持有两个常驻的测量 cell，每次 `configure` 之前
/// 先 `prepareForReuse()`，让上一次借出的块视图归还。这里直接验证
/// `AssistantMessageCell.prepareForReuse()` → `BlockStackView.recycleAll()` →
/// `BlockViewPool.recycle` 这条链路确实把视图还给了池子，做到「借出去的最终都还回来」。
@Suite("块视图池收支平衡")
@MainActor
struct BlockViewPoolBalanceTests {

    private func sealed(_ ordinal: Int, _ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: true)
    }

    private func makeCell() -> AssistantMessageCell {
        AssistantMessageCell(style: .default, reuseIdentifier: nil)
    }

    @Test("configure 借出块视图后，prepareForReuse 应把它们还给池子")
    func prepareForReuseReturnsBlockViewsToPool() {
        let pool = BlockViewPool()
        let cache = AttributedCache()
        let renderer = AttributedRenderer()
        let cell = makeCell()

        #expect(pool.idleCountForTesting(.text) == 0, "全新的池子里不应该有空闲实例")

        cell.configure(blocks: [sealed(0, "甲"), sealed(1, "乙")],
                       reasoning: nil,
                       status: .completed,
                       errorText: nil,
                       pool: pool,
                       cache: cache,
                       renderer: renderer,
                       measurer: TextKitMeasurer())

        // 借出期间，视图被 BlockStackView 持有，不应该出现在池子的空闲队列里
        #expect(pool.idleCountForTesting(.text) == 0, "块视图还在被 cell 使用，不应该已经在空闲队列里")

        cell.prepareForReuse()

        // 这是本测试要抓的核心缺陷：如果 `prepareForReuse` 没有把块视图还给池子，
        // 这里的空闲数量会停在 0，而不是变回 2。
        #expect(pool.idleCountForTesting(.text) == 2,
                "prepareForReuse 应该让 2 个 text 块视图回到池子的空闲队列")
    }

    @Test("常驻测量 cell 反复 configure/prepareForReuse，池子不会被逐渐掏空")
    func repeatedMeasureCycleKeepsPoolBalanced() {
        // 模拟 ChatViewController.measureHeight 里「常驻测量 cell」的用法：
        // 同一个 cell 反复被拿来测量不同宽度/内容，每次 configure 前先 prepareForReuse。
        let pool = BlockViewPool()
        let cache = AttributedCache()
        let renderer = AttributedRenderer()
        let cell = makeCell()
        let blocks = [sealed(0, "甲"), sealed(1, "乙"), sealed(2, "丙")]

        for _ in 0..<20 {
            cell.prepareForReuse()
            cell.configure(blocks: blocks,
                           reasoning: nil,
                           status: .completed,
                           errorText: nil,
                           pool: pool,
                           cache: cache,
                           renderer: renderer,
                           measurer: TextKitMeasurer())
        }
        cell.prepareForReuse() // 归还最后一轮借出的视图

        // 若每次测量都新建 cell（旧实现），空闲数量会随迭代次数线性增长（新建的视图
        // 从不归还，池子里堆的都是「凭空冒出来」的实例）。常驻 cell 收支平衡后，
        // 空闲数量应该恰好等于一轮用到的数量（3 个），不随迭代次数增长。
        #expect(pool.idleCountForTesting(.text) == 3,
                "20 轮 configure/prepareForReuse 后，空闲队列应恰好是本轮用到的 3 个，不多不少")
    }
}
