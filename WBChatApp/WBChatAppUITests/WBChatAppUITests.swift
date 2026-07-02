//
//  WBChatAppUITests.swift
//  WBChatAppUITests
//

import XCTest

final class WBChatAppUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 冒烟测试：发送消息后（演示模式）能流式生成并渲染出回复
    @MainActor
    func testSendMessageStreamsMockReply() throws {
        let app = XCUIApplication()
        app.launch()

        let input = app.textFields["chat.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("hello")

        let sendButton = app.buttons["chat.send"]
        XCTAssertTrue(sendButton.isEnabled)
        sendButton.tap()

        // 用户消息立即上屏
        XCTAssertTrue(app.staticTexts["hello"].waitForExistence(timeout: 5))

        // Mock 客户端按 token 流式输出，等待回复中的关键内容渲染完成
        let replyFragment = app.staticTexts["Swift 快速排序示例"]
        XCTAssertTrue(replyFragment.waitForExistence(timeout: 30))
    }

    /// 回归测试：设置页以 sheet 弹出时必须能取到 AppSettings 环境对象（曾因注入顺序崩溃）
    @MainActor
    func testOpensSettingsSheet() throws {
        let app = XCUIApplication()
        app.launch()

        let openSettings = app.buttons["前往设置配置 DeepSeek API Key"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 5))
        openSettings.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["DeepSeek API"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
