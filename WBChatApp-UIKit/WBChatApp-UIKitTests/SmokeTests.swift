import Testing
import UIKit
import Markdown
import GRDB
@testable import WBChatApp_UIKit

@Suite("工程骨架冒烟")
@MainActor
struct SmokeTests {

    @Test("Theme 可用")
    func themeIsAvailable() {
        #expect(Theme.background == UIColor.systemBackground)
    }

    @Test("swift-markdown 依赖可用")
    func markdownDependencyWorks() {
        let document = Document(parsing: "# 标题\n\n正文")
        #expect(document.childCount == 2)
    }

    @Test("GRDB 依赖可用")
    func grdbDependencyWorks() throws {
        let queue = try DatabaseQueue()
        let value = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT 1")
        }
        #expect(value == 1)
    }

    @Test("UITextView 默认由 TextKit 2 驱动")
    func textViewUsesTextKit2() {
        let textView = UITextView()
        #expect(textView.textLayoutManager != nil)
    }
}
