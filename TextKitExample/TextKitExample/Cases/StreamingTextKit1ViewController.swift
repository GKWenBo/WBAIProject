//
//  StreamingTextKit1ViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 9：TextKit 1 的增量更新，定时器驱动的流式输出。
final class StreamingTextKit1ViewController: StreamingTextViewController {

    override var caseTitle: String { "增量更新 · TextKit 1" }
    override var caseBadge: String { "TextKit 1 · 案例 9" }
    override var casePoints: [String] {
        ["往 NSTextStorage 末尾 replaceCharacters，只有新追加的字符所在的行会重排",
         "重写 NSLayoutManager.processEditing(...invalidatedRange:) 拿到失效范围，算出本次重排量",
         "切到「全量替换」对比：每块都从第 0 个字符重排，累计量随长度平方增长"]
    }

    override func makeRenderer() -> IncrementalTextRenderer {
        TextKit1IncrementalRenderer()
    }
}
