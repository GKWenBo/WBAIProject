//
//  ScreenshotCaptureTests.swift
//  WBChatAppUITests
//
//  README 截图采集：跑完后用 xcresulttool 从结果包导出附件。
//

import XCTest

final class ScreenshotCaptureTests: XCTestCase {

    @MainActor
    func testCaptureReadmeScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. 流式输出
        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("用 Swift 写一个快速排序")
        app.buttons["chat.send"].tap()
        // 点击消息区收起键盘，露出完整内容
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        Thread.sleep(forTimeInterval: 3.0)
        attach(app, name: "01_streaming")

        // 等首条回复结束
        Thread.sleep(forTimeInterval: 5.0)

        // 2. 深度思考
        app.buttons["深度思考"].firstMatch.tap()
        input.tap()
        input.typeText("为什么快速排序不稳定？")
        app.buttons["chat.send"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        let thinking = app.staticTexts["思考过程"]
        XCTAssertTrue(thinking.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2.5)
        attach(app, name: "02_deep_thinking")

        // 等第二条回复结束
        Thread.sleep(forTimeInterval: 6.0)

        // 3. 会话抽屉
        app.buttons["chat.menu"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        attach(app, name: "03_drawer")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
