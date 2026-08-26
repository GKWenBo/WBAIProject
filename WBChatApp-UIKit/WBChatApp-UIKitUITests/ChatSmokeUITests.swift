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
