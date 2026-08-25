import CoreGraphics
import Testing
@testable import WBChatApp_UIKit

@Suite("自动贴底状态机")
struct AutoScrollControllerTests {

    /// 模拟用户向上拖动
    private func dragUp(_ controller: AutoScrollController, from: CGFloat = 1000, to: CGFloat = 900) {
        controller.willBeginDragging(offsetY: from)
        controller.didScroll(offsetY: to, isTracking: true)
    }

    @Test("初始状态是贴底")
    func initialModeIsPinned() {
        #expect(AutoScrollController().mode == .pinned)
    }

    @Test("用户向上拖动脱离贴底")
    func dragUpDetaches() {
        let controller = AutoScrollController()
        dragUp(controller)
        #expect(controller.mode == .detached)
        #expect(controller.shouldStickToBottom == false)
    }

    @Test("用户向下拖动但没到底，仍保持脱离")
    func dragDownWithoutReachingBottomStaysDetached() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didScroll(offsetY: 950, isTracking: true)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 200)
        #expect(controller.mode == .detached)
    }

    @Test("松手时已在底部阈值内则恢复贴底")
    func endDraggingNearBottomRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 10)
        #expect(controller.mode == .pinned)
    }

    @Test("松手后仍在减速，此时不判定，减速结束才判定")
    func decelerationDefersDecision() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: true, distanceToBottom: 5)
        #expect(controller.mode == .detached, "还在减速就不该改变状态")
        controller.didEndDecelerating(distanceToBottom: 5)
        #expect(controller.mode == .pinned)
    }

    @Test("减速停在阈值外仍保持脱离")
    func decelerationEndFarFromBottomStaysDetached() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didEndDragging(willDecelerate: true, distanceToBottom: 500)
        controller.didEndDecelerating(distanceToBottom: 500)
        #expect(controller.mode == .detached)
    }

    @Test("程序化滚动不会让状态脱离")
    func programmaticScrollDoesNotDetach() {
        let controller = AutoScrollController()
        controller.beginProgrammaticScroll()
        controller.didScroll(offsetY: 500, isTracking: false)
        controller.endProgrammaticScroll()
        #expect(controller.mode == .pinned)
    }

    @Test("非拖动状态下的滚动不改变状态")
    func nonTrackingScrollIgnored() {
        let controller = AutoScrollController()
        controller.didScroll(offsetY: 100, isTracking: false)
        #expect(controller.mode == .pinned)
    }

    @Test("点击回到底部按钮恢复贴底")
    func tapButtonRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didTapScrollToBottom()
        #expect(controller.mode == .pinned)
    }

    @Test("发送新消息强制恢复贴底")
    func sendMessageRepins() {
        let controller = AutoScrollController()
        dragUp(controller)
        controller.didSendMessage()
        #expect(controller.mode == .pinned)
    }

    @Test("状态变化只在真正切换时回调一次")
    func modeChangeCallbackFiresOnce() {
        let controller = AutoScrollController()
        var changes: [AutoScrollController.Mode] = []
        controller.onModeChange = { changes.append($0) }

        dragUp(controller)
        controller.didScroll(offsetY: 880, isTracking: true)   // 继续向上，不该再回调
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 5)

        #expect(changes == [.detached, .pinned])
    }

    @Test("向下拖动不会触发脱离")
    func dragDownDoesNotDetach() {
        let controller = AutoScrollController()
        controller.willBeginDragging(offsetY: 900)
        controller.didScroll(offsetY: 1000, isTracking: true)
        #expect(controller.mode == .pinned)
    }

    @Test("阈值可配置")
    func thresholdIsConfigurable() {
        let controller = AutoScrollController(bottomThreshold: 100)
        dragUp(controller)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 80)
        #expect(controller.mode == .pinned)
    }

    @Test("distanceToBottom 恰好等于阈值也算贴底（锁死 <= 而非 < 的语义）")
    func thresholdBoundaryExactlyAtLimitRepins() {
        let controller = AutoScrollController(bottomThreshold: 100)
        dragUp(controller)
        controller.didEndDragging(willDecelerate: false, distanceToBottom: 100)
        #expect(controller.mode == .pinned)
    }

    @Test("已经贴底时点击回到底部按钮不应重复回调")
    func tapButtonWhenAlreadyPinnedDoesNotFireCallback() {
        let controller = AutoScrollController()
        var changes: [AutoScrollController.Mode] = []
        controller.onModeChange = { changes.append($0) }
        controller.didTapScrollToBottom()
        #expect(changes.isEmpty)
    }

    @Test("已经贴底时发送消息不应重复回调")
    func sendMessageWhenAlreadyPinnedDoesNotFireCallback() {
        let controller = AutoScrollController()
        var changes: [AutoScrollController.Mode] = []
        controller.onModeChange = { changes.append($0) }
        controller.didSendMessage()
        #expect(changes.isEmpty)
    }

    // MARK: - 程序化滚动与真实手势的交叉场景

    @Test("程序化滚动进行中用户按下手指开始真实拖动，willBeginDragging 应立即解除程序化保护让用户接管")
    func realDragDuringProgrammaticScrollDetaches() {
        let controller = AutoScrollController()
        // 「点击回到底部」发起的带动画程序化滚动仍在进行中
        controller.beginProgrammaticScroll()
        // 用户此时抓住屏幕，走完整的手势流程
        controller.willBeginDragging(offsetY: 1000)
        controller.didScroll(offsetY: 900, isTracking: true)
        #expect(controller.mode == .detached, "手指按下应无条件解除程序化滚动保护，用户接管应该成功")
    }

    @Test("程序化滚动进行中出现 isTracking: true 但未经过 willBeginDragging，防御性场景下保护仍应生效")
    func programmaticScrollGuardBlocksTrackingScrollWithoutGestureStart() {
        let controller = AutoScrollController()
        // 上一次手势遗留的起点，比新的 offsetY 更靠下——方向判定本身会认为这是「向上拖」
        controller.willBeginDragging(offsetY: 1000)
        // 程序化滚动开始（比如点击回到底部按钮的动画），但期间没有再走 willBeginDragging
        controller.beginProgrammaticScroll()
        // 直接出现一个 isTracking: true 的滚动信号（防御性场景，didScroll 顺序被打乱等）
        controller.didScroll(offsetY: 500, isTracking: true)
        #expect(controller.mode == .pinned, "没有经过手指按下信号确认接管前，程序化滚动保护应继续拦截")
    }

    @Test("嵌套/重叠的两次程序化滚动，第一次 end 不应提前解除保护")
    func nestedProgrammaticScrollsDoNotEndEarly() {
        let controller = AutoScrollController()
        controller.willBeginDragging(offsetY: 1000)
        controller.beginProgrammaticScroll() // 外层程序化滚动开始
        controller.beginProgrammaticScroll() // 内层（重叠的）程序化滚动开始
        controller.endProgrammaticScroll()   // 内层结束，外层仍未结束
        controller.didScroll(offsetY: 500, isTracking: true)
        #expect(controller.mode == .pinned, "外层程序化滚动还没结束，保护不应解除")
        controller.endProgrammaticScroll()   // 外层结束，保护才应完全解除
    }

    @Test("endProgrammaticScroll 在计数已为 0 时不应减成负数")
    func endProgrammaticScrollNeverGoesNegative() {
        let controller = AutoScrollController()
        controller.endProgrammaticScroll() // 多余的一次 end，此时计数本就是 0
        controller.beginProgrammaticScroll()
        controller.endProgrammaticScroll()
        // 若计数被减成负数，之后配平的一对 begin/end 会让深度停留在 -1，
        // 导致 didScroll 的守卫误判为「仍在程序化滚动中」
        dragUp(controller)
        #expect(controller.mode == .detached)
    }
}
