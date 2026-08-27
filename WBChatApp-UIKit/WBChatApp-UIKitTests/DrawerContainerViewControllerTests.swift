import UIKit
import Testing
@testable import WBChatApp_UIKit

/// I4 修复：抽屉已展开时从左边缘拖动，不应该先"闪回" x = 0 再跟手。
///
/// 根因：`handleEdgePan` 的 `.changed` 分支此前直接拿 `translation`（从手指落下那一刻
/// 算起，恒以 0 起步）当作 content 的新 x，完全不看拖动开始前 content 已经在哪。
/// 抽屉展开时 content 本在 `x = drawerWidth`，手指一动（`translation` 还很小）就会把
/// x 摁回接近 0 的位置。`.ended` 同理用原始 translation 判定开合，与「已经展开、
/// 只是往回收一点」的真实意图不符。
@Suite("抽屉容器手势")
@MainActor
struct DrawerContainerViewControllerTests {

    /// 宽度选够大（500），让 `drawerWidth = min(500 * 0.8, 320)` 恒为封顶值 320，
    /// 不用在每个测试里重新算。
    private static let windowWidth: CGFloat = 500
    private static let drawerWidth: CGFloat = 320

    private func make() -> (vc: DrawerContainerViewController, content: UIViewController, window: UIWindow) {
        let drawer = UIViewController()
        let content = UIViewController()
        let vc = DrawerContainerViewController(drawer: drawer, content: content)

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.windowWidth, height: 800))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.layoutIfNeeded()

        return (vc, content, window)
    }

    @Test("抽屉展开态下，边缘拖动的 .changed 不会把 content 摁回 x = 0")
    func changedDoesNotSnapBackToZeroWhenAlreadyOpen() {
        let (vc, content, window) = make()

        // 先把抽屉打开：setDrawer(open:animated:) 内部的 UIView.animate 闭包体本身
        // 是同步执行的（Core Animation 只是拿它计算出的最终值去做隐式动画），
        // 调用返回时 content 的 frame 已经是最终态，不用等动画播完。
        vc.toggleDrawer()
        #expect(content.view.frame.origin.x == Self.drawerWidth, "前置条件：抽屉已经展开")

        // 从边缘按下（.began 记录起点 = 320），然后往右继续拖一点点
        vc.simulateEdgePanForTesting(state: .began, translationX: 0)
        vc.simulateEdgePanForTesting(state: .changed, translationX: 10)

        // 手指只往右挪了 10pt，content 应该仍然停在接近 drawerWidth 的位置，
        // 而不是被摁回 0——那才是这条 bug 的症状。
        #expect(content.view.frame.origin.x > Self.drawerWidth - 20,
                "抽屉展开态下拖一点点不该把 content 摁回接近 0 的位置")

        withExtendedLifetime(window) {}
    }

    @Test("抽屉展开态下，.changed 的位移应该叠加在拖动起点上，而不是从 0 重新计数")
    func changedTracksFromDragStartNotZero() {
        let (vc, content, window) = make()

        vc.toggleDrawer()
        vc.simulateEdgePanForTesting(state: .began, translationX: 0)
        vc.simulateEdgePanForTesting(state: .changed, translationX: -100)

        // 新逻辑：x = clamp(dragStartX(320) + translation(-100), 0...320) = 220
        #expect(abs(content.view.frame.origin.x - 220) < 1)

        withExtendedLifetime(window) {}
    }

    @Test("抽屉展开态下，往回收一点松手仍判定为保持展开（基于最终位置而非原始 translation）")
    func endedUsesFinalPositionWhileAlreadyOpen() {
        let (vc, content, window) = make()

        vc.toggleDrawer()
        #expect(content.view.frame.origin.x == Self.drawerWidth)

        // dragStartX = 320，往左收 100pt，最终位置 220 > drawerWidth/2(160)，
        // 应该判定为「仍然展开」。若按旧逻辑直接拿 translation(-100) 和
        // drawerWidth/2 比，-100 > 160 为假，会被误判成「关闭」。
        vc.simulateEdgePanForTesting(state: .began, translationX: 0)
        vc.simulateEdgePanForTesting(state: .changed, translationX: -100)
        vc.simulateEdgePanForTesting(state: .ended, translationX: -100)

        #expect(content.view.frame.origin.x == Self.drawerWidth,
                "已经展开的抽屉，往回收一点松手应该保持展开，不该被误关闭")

        withExtendedLifetime(window) {}
    }

    @Test("抽屉关闭态下，从边缘拖过半应该正常触发展开（回归保护）")
    func openFromClosedStateStillWorks() {
        let (vc, content, window) = make()

        #expect(content.view.frame.origin.x == 0, "前置条件：抽屉初始是关闭的")

        vc.simulateEdgePanForTesting(state: .began, translationX: 0)
        vc.simulateEdgePanForTesting(state: .changed, translationX: Self.drawerWidth * 0.7)
        vc.simulateEdgePanForTesting(state: .ended, translationX: Self.drawerWidth * 0.7)

        #expect(content.view.frame.origin.x == Self.drawerWidth,
                "关闭态下拖过一半应该正常展开，这条修复不能破坏原有的开抽屉手势")

        withExtendedLifetime(window) {}
    }
}
