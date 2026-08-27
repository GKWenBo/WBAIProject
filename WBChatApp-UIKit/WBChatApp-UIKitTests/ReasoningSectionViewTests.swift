import UIKit
import Testing
@testable import WBChatApp_UIKit

/// C2 修复：思考过程折叠区展开态的生命周期。
@Suite("思考过程折叠区")
@MainActor
struct ReasoningSectionViewTests {

    @Test("点击标题栏切换展开态，并触发 onToggle")
    func toggleFlipsExpandedStateAndFiresCallback() {
        let view = ReasoningSectionView()
        view.setText("这是思考过程")

        var toggleCount = 0
        view.onToggle = { toggleCount += 1 }

        #expect(view.isExpandedForTesting == false)

        view.simulateToggleForTesting()
        #expect(view.isExpandedForTesting == true)
        #expect(toggleCount == 1)

        view.simulateToggleForTesting()
        #expect(view.isExpandedForTesting == false)
        #expect(toggleCount == 2)
    }

    @Test("展开后高度应大于折叠态")
    func expandedHeightIsLargerThanCollapsed() {
        let view = ReasoningSectionView()
        let longText = String(repeating: "这是很长的思考内容，需要好几行才能显示完整。", count: 10)
        view.setText(longText)

        let collapsedHeight = view.heightThatFits(width: 300)
        view.simulateToggleForTesting()
        let expandedHeight = view.heightThatFits(width: 300)

        #expect(expandedHeight > collapsedHeight,
                "展开后应该测出更大的高度，否则上层无法据此扩大行高，内容会被裁")
    }

    @Test("collapse() 把展开态收起，不触发 onToggle（C2）")
    func collapseResetsExpandedStateWithoutFiringCallback() {
        let view = ReasoningSectionView()
        view.setText("这是思考过程")
        view.simulateToggleForTesting()
        #expect(view.isExpandedForTesting == true)

        var toggleCount = 0
        view.onToggle = { toggleCount += 1 }

        view.collapse()

        #expect(view.isExpandedForTesting == false)
        #expect(toggleCount == 0, "collapse() 是 cell 复用时的静默复位，不该像用户点击一样再喊一次 onToggle")
    }

    @Test("已经是折叠态时调用 collapse() 是安全的空操作")
    func collapseOnAlreadyCollapsedIsNoOp() {
        let view = ReasoningSectionView()
        view.setText("这是思考过程")
        #expect(view.isExpandedForTesting == false)

        view.collapse()
        #expect(view.isExpandedForTesting == false)
    }
}
