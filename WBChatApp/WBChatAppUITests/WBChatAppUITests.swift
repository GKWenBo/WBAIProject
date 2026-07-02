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
        attachScreenshot(named: "settings")
    }

    /// 生成 README 用的三张截图（流式输出 / 深度思考 / 抽屉），从测试结果包导出
    @MainActor
    func testCaptureReadmeScreenshots() throws {
        var app = launchSeededApp()

        // 1. 流式输出中途截图（种子草稿已预填，直接发送）
        app.buttons["chat.send"].tap()
        sleep(3)
        attachScreenshot(named: "streaming")

        // 等首条回复渲染完成
        XCTAssertTrue(app.staticTexts["Swift 快速排序示例"].waitForExistence(timeout: 30))

        // 2. 重启拿到新的种子草稿，开深度思考后发送，截推理过程
        app.terminate()
        app = launchSeededApp()
        app.buttons["深度思考"].tap()
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["思考过程"].waitForExistence(timeout: 10))
        sleep(2)
        attachScreenshot(named: "deep-thinking")

        // 3. 打开抽屉截会话列表（含时间分组）
        XCTAssertTrue(app.staticTexts["Swift 快速排序示例"].waitForExistence(timeout: 30))
        app.buttons["chat.menu"].tap()
        sleep(1)
        attachScreenshot(named: "drawer")
    }

    @MainActor
    private func launchSeededApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-seed"]
        app.launch()
        XCTAssertTrue(app.textFields["chat.input"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
