//
//  StreamingTextKit2ViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 10：TextKit 2 的增量更新，定时器驱动的流式输出。
final class StreamingTextKit2ViewController: StreamingTextViewController {

    override var caseTitle: String { "增量更新 · TextKit 2" }
    override var caseBadge: String { "TextKit 2 · 案例 10" }
    override var casePoints: [String] {
        ["排版结果按段落缓存：追加时只有最后一段重新生成 NSTextLayoutFragment",
         "编辑放进 performEditingTransaction；直接改 textView.text 等于全量替换",
         "重排量靠 NSTextLayoutManagerDelegate 统计新建了几个 fragment"]
    }

    override func makeRenderer() -> IncrementalTextRenderer {
        TextKit2IncrementalRenderer()
    }
}
