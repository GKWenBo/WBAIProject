import XCTest

/// 抽屉交互的真机（模拟器）验证：用真实触摸手势驱动，覆盖单元测试碰不到的部分——
/// 手势与列表滚动的共存、起手区域限制、以及展开后的视觉层次。
///
/// 每个关键状态都会把截图附加到测试结果，便于人工核对圆角、阴影、视差与遮罩。
final class DrawerInteractionUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDrawerInteraction() {
        let app = XCUIApplication()
        app.launch()

        let menu = app.buttons["chat.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5), "聊天页应有菜单按钮")

        let drawerTable = app.tables["drawer.tableView"]
        let chatTable = app.tables["chat.tableView"]
        XCTAssertTrue(drawerTable.waitForExistence(timeout: 5))
        XCTAssertTrue(chatTable.waitForExistence(timeout: 5))

        // 1. 初始关闭态：抽屉被主内容完全盖住，不可点击
        XCTAssertFalse(drawerTable.isHittable, "关闭态抽屉不该可交互")
        shot(app, "01-closed")

        // 2. 关闭态从屏幕中部起手右滑：起手区域限制生效，抽屉不该被拽出来。
        //    拖距要超过 drawerWidth/2（≈屏宽 0.40），否则「没过半弹回」会让
        //    这条断言在没有区域限制时也照样通过，测不出东西
        slowDrag(app, fromX: 0.5, toX: 0.95)
        XCTAssertFalse(drawerTable.isHittable, "关闭态只有屏幕左侧区域能拉出抽屉")

        // 3. 关闭态从左侧区域右滑：正常拉出
        drag(app, fromX: 0.03, toX: 0.75)
        XCTAssertTrue(waitUntil { drawerTable.isHittable }, "从左边缘右滑应展开抽屉")
        shot(app, "02-opened-by-gesture")

        // 4. 展开态在抽屉里纵向滑动列表：方向锁应把触摸交给滚动，抽屉保持展开
        drag(app, fromX: 0.2, toX: 0.2, fromY: 0.7, toY: 0.3)
        XCTAssertTrue(drawerTable.isHittable, "纵向滑动列表不该把抽屉滑走")

        // 5. 展开态从任意位置左滑收起：这是旧实现（仅边缘手势）做不到的
        drag(app, fromX: 0.9, toX: 0.2)
        XCTAssertTrue(waitUntil { !drawerTable.isHittable }, "展开态任意位置左滑都应收起抽屉")
        shot(app, "03-closed-by-gesture")

        // 6. 菜单按钮开关
        menu.tap()
        XCTAssertTrue(waitUntil { drawerTable.isHittable }, "点菜单应展开抽屉")
        let settings = app.buttons["drawer.settings"]
        XCTAssertTrue(settings.isHittable)
        XCTAssertLessThanOrEqual(settings.frame.maxX, chatTable.frame.minX)
        XCTAssertLessThanOrEqual(drawerTable.frame.maxX, chatTable.frame.minX)
        shot(app, "04-opened-by-menu")

        // 7. 点主内容区域（遮罩）关闭
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(waitUntil { !drawerTable.isHittable }, "点主内容应收起抽屉")
        shot(app, "05-closed-by-dimming-tap")
    }

    /// 抽屉里行左滑呼出「删除/重命名」：这是行自己的横向手势，
    /// 抽屉不能同时跟着动，否则划出删除按钮的同时列表就没了
    func testRowSwipeDoesNotCloseDrawer() {
        let app = XCUIApplication()
        app.launch()

        let menu = app.buttons["chat.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()

        let drawerTable = app.tables["drawer.tableView"]
        XCTAssertTrue(waitUntil { drawerTable.isHittable }, "前置条件：抽屉已打开")

        let row = drawerTable.cells.element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 3), "抽屉应有至少一行")
        row.swipeLeft()

        XCTAssertTrue(waitUntil(timeout: 2) { app.buttons["删除"].exists },
                      "行左滑应呼出删除按钮")
        XCTAssertTrue(drawerTable.isHittable, "行左滑是行的手势，不该把抽屉一起收走")
        shot(app, "08-row-swipe-keeps-drawer-open")
    }

    /// 起手没过半且慢速松手：应弹回关闭态，而不是留在半开位置
    func testSnapsBackWhenReleasedBelowHalfway() {
        let app = XCUIApplication()
        app.launch()

        let drawerTable = app.tables["drawer.tableView"]
        XCTAssertTrue(drawerTable.waitForExistence(timeout: 5))
        XCTAssertFalse(drawerTable.isHittable)

        // 屏宽 402pt 时 drawerWidth = min(402 * 0.82, 320) = 320，
        // 一半是 160pt ≈ 屏宽的 0.40。这里只拖到 0.33 就松手
        slowDrag(app, fromX: 0.03, toX: 0.33)

        XCTAssertTrue(waitUntil { !drawerTable.isHittable },
                      "没过半松手应弹回关闭态")
        shot(app, "06-snap-back-below-halfway")
    }

    /// 起手过半且慢速松手：应吸附到完全展开
    func testSnapsOpenWhenReleasedAboveHalfway() {
        let app = XCUIApplication()
        app.launch()

        let drawerTable = app.tables["drawer.tableView"]
        XCTAssertTrue(drawerTable.waitForExistence(timeout: 5))
        XCTAssertFalse(drawerTable.isHittable)

        slowDrag(app, fromX: 0.03, toX: 0.55)

        XCTAssertTrue(waitUntil { drawerTable.isHittable },
                      "过半松手应吸附到完全展开")
        shot(app, "07-snap-open-above-halfway")
    }

    // MARK: - Helpers

    private func drag(_ app: XCUIApplication,
                     fromX: CGFloat, toX: CGFloat,
                     fromY: CGFloat = 0.5, toY: CGFloat = 0.5) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// 慢速拖动：把速度压在甩动阈值（500pt/s）以下，
    /// 这样吸附结果只由「松手时的位置」决定，测的是位置兜底分支
    private func slowDrag(_ app: XCUIApplication, fromX: CGFloat, toX: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    /// 手势后的归位动画需要时间，轮询等待而不是死等固定时长
    private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
