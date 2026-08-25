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
}
