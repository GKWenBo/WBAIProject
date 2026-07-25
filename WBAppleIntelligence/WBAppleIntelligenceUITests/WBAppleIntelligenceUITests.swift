import XCTest

/// 首页冒烟测试。
///
/// 只验一件事：App 能起来，并且停在「能力目录」这一页上。
/// 不测四个 Demo 的生成结果——本工程的开发环境里端侧模型不可用（详见 Docs/README.md 第 3 节），
/// 任何依赖真实生成的断言都会变成一条时灵时不灵的测试。
final class WBAppleIntelligenceUITests: XCTestCase {

    override func setUpWithError() throws {
        // UI 测试一旦失败，后续步骤基本都建立在错误的界面状态上，继续跑只会产生噪声。
        continueAfterFailure = false
    }

    @MainActor
    func testHomeShowsCapabilityCatalog() throws {
        let app = XCUIApplication()
        app.launch()

        // 用导航栏标题而不是某个 Demo 入口做断言：标题是这一页的身份标识，
        // 后续增删能力条目都不会影响这条断言。
        let title = app.navigationBars["端侧 AI 能力"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 10),
            "App 启动后没有停在能力目录首页"
        )
    }
}
