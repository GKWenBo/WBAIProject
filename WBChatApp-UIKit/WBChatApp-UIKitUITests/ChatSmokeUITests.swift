import XCTest

final class ChatSmokeUITests: XCTestCase {

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// 演示模式下发一条消息，确认助手气泡出现且能滚动
    func testSendMessageInMockMode() {
        let app = XCUIApplication()
        app.launch()

        let input = app.textViews["input.textView"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("你好")

        app.buttons["input.send"].tap()

        // 演示模式会流式吐出一段带代码块的 Markdown
        let table = app.tables["chat.tableView"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        let expectation = expectation(description: "等待流式输出结束")
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { expectation.fulfill() }
        wait(for: [expectation], timeout: 10)

        XCTAssertGreaterThanOrEqual(table.cells.count, 2, "应至少有用户与助手两条消息")
    }
}

extension ChatSmokeUITests {
    func testDraftSurvivesConversationSwitchAndForeground() {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["chat.menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["drawer.newConversation"].tap()
        let input = app.textViews["input.textView"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("draft lifecycle")
        menu.tap()
        app.buttons["drawer.newConversation"].tap()
        XCTAssertEqual(input.value as? String, "")
        menu.tap()
        let rows = app.tables["drawer.tableView"].cells
        XCTAssertGreaterThanOrEqual(rows.count, 2)
        rows.element(boundBy: 1).tap()
        XCTAssertEqual(input.value as? String, "draft lifecycle")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(input.value as? String, "draft lifecycle")
        let send = app.buttons["input.send"]
        // activate 返回时系统缩放动画仍可能影响 XCTest 的命中坐标。
        // 等待输入栏回到窗口右下角，再点击按钮当前几何中心。
        let settled = NSPredicate { _, _ in
            send.isHittable && abs(send.frame.maxX - (app.frame.maxX - 12)) < 2
                && send.frame.midY > app.frame.height * 0.9
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 5), .completed)
        send.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let table = app.tables["chat.tableView"]
        let finished = NSPredicate { _, _ in app.buttons["input.send"].exists && table.cells.count == 2 }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: finished, object: nil)], timeout: 15)
        if result != .completed {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.lifetime = .keepAlways
            add(image)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, "发送后消息数量：\(table.cells.count)")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(table.cells.count, 2, "恢复前台不得重复创建请求或消息")
        XCTAssertEqual(input.value as? String, "")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
