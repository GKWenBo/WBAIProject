import UIKit
import Testing
@testable import WBChatApp_UIKit

/// 抽屉容器手势状态机。
///
/// 三组回归保护：
/// - I4：抽屉已展开时拖动，位移必须叠加在拖动起点上，不能从 0 重新计数
///   （旧实现直接拿 translation 当新 x，抽屉「开着往右拖」会先闪回关闭态）；
/// - 方向锁：纵向滑动只归列表滚动，抽屉全程不动；一旦判定纵向，
///   即使中途横向位移占优也不再接管，保证同一时刻只响应一个方向；
/// - 甩动优先：速度过阈值时按甩动方向吸附，不看当前停在哪。
///
/// 驱动方式说明：真实手势的第一段位移会被当成「方向试探」扣掉
/// （`axisLockThreshold` = 12pt），所以用例一律按两段式驱动——先给一小段
/// 触发方向锁，再给真正的拖动量。这与手指在屏幕上的实际过程一致，
/// 也是「扣掉启动阈值」这条修复必须被覆盖到的地方。
@Suite("抽屉容器手势")
@MainActor
struct DrawerContainerViewControllerTests {

    /// 宽度选够大（500），让 `drawerWidth = min(500 * 0.82, 320)` 恒为封顶值 320，
    /// 不用在每个测试里重新算。
    private static let windowWidth: CGFloat = 500
    private static let drawerWidth: CGFloat = 320

    private func make(content: UIViewController? = nil)
    -> (vc: DrawerContainerViewController, window: UIWindow) {
        let drawer = UIViewController()
        let vc = DrawerContainerViewController(drawer: drawer, content: content ?? UIViewController())

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.windowWidth, height: 800))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.layoutIfNeeded()

        return (vc, window)
    }

    // MARK: - I4：位移叠加在拖动起点上

    @Test("抽屉展开态下拖动，不会把 content 摁回 x = 0")
    func changedDoesNotSnapBackToZeroWhenAlreadyOpen() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        #expect(vc.contentOriginXForTesting == Self.drawerWidth, "前置条件：抽屉已经展开")

        // 15pt 触发方向锁，再往右多拖 10pt
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 15)
        vc.simulatePanForTesting(state: .changed, translationX: 25)

        #expect(vc.contentOriginXForTesting > Self.drawerWidth - 20,
                "抽屉展开态下拖一点点不该把 content 摁回接近 0 的位置")

        withExtendedLifetime(window) {}
    }

    @Test("拖动位移叠加在起点上：锁定前那一段被扣掉，之后才跟手")
    func changedTracksFromDragStartNotZero() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: -15)
        vc.simulatePanForTesting(state: .changed, translationX: -100)

        // 起点 320，锁定扣掉前 15pt，真实拖动量 -85 → 320 - 85 = 235。
        // 若按旧逻辑从 0 计数，会得到 max(0, -100) = 0，抽屉直接闪回关闭态。
        #expect(abs(vc.contentOriginXForTesting - 235) < 1)

        withExtendedLifetime(window) {}
    }

    @Test("已展开的抽屉往回收一点松手，仍判定为保持展开")
    func endedUsesFinalPositionWhileAlreadyOpen() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: -15)
        vc.simulatePanForTesting(state: .changed, translationX: -100)
        vc.simulatePanForTesting(state: .ended, translationX: -100)

        // 最终停在 235 > drawerWidth/2(160)，应保持展开
        #expect(vc.contentOriginXForTesting == Self.drawerWidth,
                "已经展开的抽屉，往回收一点松手不该被误关闭")

        withExtendedLifetime(window) {}
    }

    @Test("关闭态下拖过半应该正常展开（回归保护）")
    func openFromClosedStateStillWorks() {
        let (vc, window) = make()

        #expect(vc.contentOriginXForTesting == 0, "前置条件：抽屉初始是关闭的")

        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 15)
        vc.simulatePanForTesting(state: .changed, translationX: 224)
        vc.simulatePanForTesting(state: .ended, translationX: 224)

        // 实际拖动量 209 > 160
        #expect(vc.contentOriginXForTesting == Self.drawerWidth,
                "关闭态下拖过一半应该正常展开，这条修复不能破坏原有的开抽屉手势")

        withExtendedLifetime(window) {}
    }

    // MARK: - 方向锁

    @Test("纵向滑动时抽屉全程不动，触摸交还给列表滚动")
    func verticalDragDoesNotMoveDrawer() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0, translationY: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 4, translationY: 60)
        vc.simulatePanForTesting(state: .changed, translationX: 6, translationY: 180)

        #expect(vc.contentOriginXForTesting == Self.drawerWidth,
                "判为纵向后抽屉不该有任何位移")

        withExtendedLifetime(window) {}
    }

    @Test("方向一旦锁定为纵向，中途横向位移占优也不再接管")
    func axisStaysLockedForWholeGesture() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0, translationY: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 4, translationY: 60)
        // 斜着划到横向明显占优：方向已锁定，抽屉必须继续不动
        vc.simulatePanForTesting(state: .changed, translationX: 260, translationY: 60)

        #expect(vc.contentOriginXForTesting == Self.drawerWidth,
                "同一时刻只响应一个方向，纵向锁定后横向不得中途抢走手势")

        withExtendedLifetime(window) {}
    }

    @Test("方向判定前的小幅抖动不移动抽屉")
    func subThresholdMovementDoesNotMoveDrawer() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0, translationY: 0)
        // 累计位移 8pt < 阈值 12pt：还没判定方向，不该抢走列表滚动、也不该动
        vc.simulatePanForTesting(state: .changed, translationX: 6, translationY: 8)

        #expect(vc.contentOriginXForTesting == Self.drawerWidth)

        withExtendedLifetime(window) {}
    }

    // MARK: - 甩动吸附

    @Test("位置没过半但甩动够快，按甩动方向展开")
    func flickOpensEvenBelowHalfway() {
        let (vc, window) = make()

        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 15)
        vc.simulatePanForTesting(state: .changed, translationX: 95)
        vc.simulatePanForTesting(state: .ended, translationX: 95, velocityX: 900)

        // 停在 80（远不到 160），靠甩动速度展开
        #expect(vc.contentOriginXForTesting == Self.drawerWidth)

        withExtendedLifetime(window) {}
    }

    @Test("位置过半但反向甩动够快，按甩动方向收起")
    func flickClosesEvenAboveHalfway() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: -15)
        vc.simulatePanForTesting(state: .changed, translationX: -60)
        vc.simulatePanForTesting(state: .ended, translationX: -60, velocityX: -900)

        // 停在 275（过半），但向左甩得够快，仍应收起
        #expect(vc.contentOriginXForTesting == 0)

        withExtendedLifetime(window) {}
    }

    // MARK: - 边界与视觉

    @Test("拖过头时被钳制在 [0, drawerWidth]，不会露出下层背景")
    func dragIsClampedToBounds() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 15)
        vc.simulatePanForTesting(state: .changed, translationX: 600)
        #expect(vc.contentOriginXForTesting == Self.drawerWidth, "向右拖过头不该超过 drawerWidth")

        vc.simulatePanForTesting(state: .changed, translationX: -600)
        #expect(vc.contentOriginXForTesting == 0, "向左拖过头不该变成负数")

        withExtendedLifetime(window) {}
    }

    @Test("圆角随展开进度变化：关闭态为 0，展开态为最大值")
    func cornerRadiusFollowsProgress() {
        let (vc, window) = make()

        #expect(vc.contentCornerRadiusForTesting == 0,
                "关闭态圆角必须是 0，否则四角会被切掉并露出下层背景")

        vc.setDrawerForTesting(open: true)
        #expect(vc.contentCornerRadiusForTesting > 0, "展开态应长出圆角")

        withExtendedLifetime(window) {}
    }

    @Test("展开态卡片上下让出抽屉，关闭态占满全高")
    func verticalInsetFollowsProgress() {
        let (vc, window) = make()

        #expect(vc.contentVerticalInsetForTesting == 0,
                "关闭态卡片必须占满全高，否则上下会露出抽屉、边缘出现缺口")

        vc.setDrawerForTesting(open: true)
        #expect(vc.contentVerticalInsetForTesting > 0,
                "展开态卡片应上下让出抽屉，缺口与缝隙才露得出来")

        withExtendedLifetime(window) {}
    }

    @Test("遮罩与卡片逐像素重合，不会在圆角缺口切出直角暗块")
    func dimmingMatchesCardShape() {
        let (vc, window) = make()

        vc.setDrawerForTesting(open: true)
        let card = vc.cardFrameForTesting
        let dimming = vc.dimmingFrameForTesting

        // 只有重合，圆角外侧那块缺口才不会被遮罩单独压暗一层
        #expect(abs(card.minX - dimming.minX) < 0.01)
        #expect(abs(card.minY - dimming.minY) < 0.01)
        #expect(abs(card.height - dimming.height) < 0.01)
        #expect(vc.dimmingCornerRadiusForTesting > 0, "遮罩必须跟随卡片圆角")

        withExtendedLifetime(window) {}
    }

    // MARK: - 手势收尾与布局补位

    /// .failed 也必须还原滚动：只处理 .ended/.cancelled 的话，
    /// 手势被系统判失败时列表会永久停在「禁用了滚动」的状态
    @Test("手势 .failed 时还原临时禁用的滚动，列表不会永久滚不动")
    func failedGestureRestoresScrolling() async throws {
        let tableVC = UIViewController()
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: Self.windowWidth, height: 800))
        tableVC.view.addSubview(table)

        let (vc, window) = make(content: tableVC)

        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: 20)
        let during = table.isScrollEnabled

        UIView.performWithoutAnimation {
            vc.simulatePanForTesting(state: .failed, translationX: 20)
        }
        try await Task.sleep(for: .seconds(1))
        let restored = table.isScrollEnabled

        #expect(during == false && restored,
                "PROBE 拖动中禁用=\(during) 失败后还原=\(restored)")

        withExtendedLifetime(window) {}
    }

    /// 归位动画期间 `viewDidLayoutSubviews` 是被 isSettling 挡掉的，
    /// 动画结束后必须补一次布局，否则卡片会一直停在旧尺寸上
    @Test("归位动画期间发生旋转，动画结束后会补一次布局")
    func layoutIsReappliedAfterSettleWhenBoundsChanged() {
        let (vc, window) = make()

        vc.toggleDrawer()
        window.frame = CGRect(x: 0, y: 0, width: 900, height: 500)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        RunLoop.current.run(until: Date().addingTimeInterval(0.2))

        #expect(vc.cardFrameForTesting.width == 900,
                "旋转发生在归位动画中，动画结束后卡片必须跟上新宽度")
        #expect(vc.cardFrameForTesting.height == 500 - 2 * vc.contentVerticalInsetForTesting,
                "高度同样要跟上新尺寸")

        withExtendedLifetime(window) {}
    }

    /// 归位动画期间换主内容时，新内容的 frame 必须当场给：
    /// 随后那次布局会被 `isSettling` 挡掉，新内容会一直停在默认尺寸上
    @Test("归位动画进行中换主内容，新内容当场拿到与卡片一致的 frame")
    func setContentAppliesCardFrameImmediately() {
        let (vc, window) = make()

        vc.toggleDrawer() // 动画进行中
        let newContent = UIViewController()
        vc.setContent(newContent)

        #expect(abs(newContent.view.frame.width - vc.cardFrameForTesting.width) < 0.01)
        #expect(newContent.view.frame.height == vc.cardFrameForTesting.height,
                "新内容高度要跟卡片一致，否则底部圆角裁不到它、会露出一条直边")

        withExtendedLifetime(window) {}
    }

    @Test("toggleDrawer 调用返回时位置已是终态（动画闭包同步执行）")
    func toggleAppliesFinalFrameSynchronously() {
        let (vc, window) = make()

        vc.toggleDrawer()
        #expect(vc.isOpenForTesting)
        #expect(vc.contentOriginXForTesting == Self.drawerWidth,
                "动画闭包体同步执行，调用返回时 frame 已是最终态，不用等动画播完")

        withExtendedLifetime(window) {}
    }
}

@Suite("抽屉布局与滚动回归")
@MainActor
struct DrawerLayoutRegressionTests {
    @Test("展开后抽屉全部位于卡片左侧", arguments: [320.0, 402.0, 900.0])
    func drawerFitsVisibleArea(width: Double) {
        let drawer = UIViewController()
        let vc = DrawerContainerViewController(drawer: drawer, content: UIViewController())
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: width, height: 800)
        vc.setDrawerForTesting(open: true)
        #expect(drawer.view.frame.maxX <= vc.cardFrameForTesting.minX)
    }

    @Test("开始回调已达到横向阈值时立即暂停滚动")
    func horizontalBeganSuspendsScrolling() async throws {
        let content = UIViewController()
        let table = UITableView()
        content.view.addSubview(table)
        let vc = DrawerContainerViewController(drawer: UIViewController(), content: content)
        vc.loadViewIfNeeded()
        vc.simulatePanForTesting(state: .began, translationX: 20, translationY: 2)
        #expect(!table.isScrollEnabled)
        UIView.performWithoutAnimation {
            vc.simulatePanForTesting(state: .cancelled, translationX: 20)
        }
        try await Task.sleep(for: .seconds(1))
        #expect(table.isScrollEnabled)
    }

    @Test("侧滑途中换内容时恢复旧列表并暂停新列表")
    func replacingContentTransfersScrollSuspension() async throws {
        let oldContent = UIViewController()
        let oldTable = UITableView()
        oldContent.view.addSubview(oldTable)
        let vc = DrawerContainerViewController(drawer: UIViewController(), content: oldContent)
        vc.loadViewIfNeeded()
        vc.simulatePanForTesting(state: .began, translationX: 20)
        let newContent = UIViewController()
        let newTable = UITableView()
        newContent.view.addSubview(newTable)
        vc.setContent(newContent)
        #expect(oldTable.isScrollEnabled)
        #expect(!newTable.isScrollEnabled)
        UIView.performWithoutAnimation {
            vc.simulatePanForTesting(state: .ended, translationX: 20)
        }
        try await Task.sleep(for: .seconds(1))
        #expect(newTable.isScrollEnabled)
    }

    @Test("归位动画完成前保持禁用，完成后恢复")
    func scrollingResumesAfterAnimation() async throws {
        let content = UIViewController()
        let scroll = UIScrollView()
        content.view.addSubview(scroll)
        let vc = DrawerContainerViewController(drawer: UIViewController(), content: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = vc
        window.makeKeyAndVisible()
        vc.view.layoutIfNeeded()
        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: -20)
        vc.simulatePanForTesting(state: .changed, translationX: -100)
        vc.simulatePanForTesting(state: .ended, translationX: -100)
        #expect(!scroll.isScrollEnabled)
        try await Task.sleep(for: .seconds(1))
        #expect(scroll.isScrollEnabled)
        withExtendedLifetime(window) {}
    }

    @Test("横向拖动暂停深层滚动并保留原有禁用状态")
    func nestedScrollingIsSuspended() async throws {
        let content = UIViewController()
        var parent = content.view!
        for _ in 0..<8 {
            let child = UIView()
            parent.addSubview(child)
            parent = child
        }
        let chat = UIScrollView()
        let disabled = UIScrollView()
        disabled.isScrollEnabled = false
        parent.addSubview(chat)
        parent.addSubview(disabled)
        let drawer = UIViewController()
        let list = UITableView()
        drawer.view.addSubview(list)
        let vc = DrawerContainerViewController(drawer: drawer, content: content)
        vc.loadViewIfNeeded()
        vc.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        vc.setDrawerForTesting(open: true)
        vc.simulatePanForTesting(state: .began, translationX: 0)
        vc.simulatePanForTesting(state: .changed, translationX: -20)
        #expect(!chat.isScrollEnabled)
        #expect(!list.isScrollEnabled)
        UIView.performWithoutAnimation {
            vc.simulatePanForTesting(state: .cancelled, translationX: -20)
        }
        try await Task.sleep(for: .seconds(1))
        #expect(chat.isScrollEnabled)
        #expect(list.isScrollEnabled)
        #expect(!disabled.isScrollEnabled)
    }
}
