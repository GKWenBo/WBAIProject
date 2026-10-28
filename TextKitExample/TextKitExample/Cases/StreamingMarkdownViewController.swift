//
//  StreamingMarkdownViewController.swift
//  TextKitExample
//

import UIKit

/// 案例 11：Markdown 流式渲染 —— 冻结已闭合块，只重渲染尾块。
///
/// 和案例 10 共用同一个演示页，区别在于吐出的是 Markdown，而且更新由 `MarkdownStreamSession` 调度：
/// - 只替换尾块：已闭合的块渲染一次就冻结，每块新文本只重渲染并替换尾块。
/// - 全量重渲染：每次把全部原文重新渲染再整体替换，作为对照。
final class StreamingMarkdownViewController: StreamingTextViewController {

    override var caseTitle: String { "Markdown 流式渲染" }
    override var caseBadge: String { "TextKit 2 · 案例 11" }
    override var casePoints: [String] {
        ["空行切块（围栏代码块里的空行不算），已闭合的块渲染一次就冻结",
         "尾块每次从块起点整体重渲染再 replaceTail，半截的 **加粗、代码围栏也不会丢属性",
         "原文和渲染结果不等长，要分别记录两套偏移；切到「全量重渲染」对比重排量"]
    }

    override var sampleText: String { SampleText.streamingMarkdown }
    override var modeTitles: [String] { ["只替换尾块", "全量重渲染"] }

    private lazy var session = MarkdownStreamSession(renderer: renderer)

    override func makeRenderer() -> IncrementalTextRenderer {
        TextKit2IncrementalRenderer()
    }

    override func applyUpdate(chunk: String, emitted: String, replacingAll: Bool) -> IncrementalUpdateReport {
        replacingAll ? session.replaceAll(with: emitted) : session.append(chunk)
    }

    override func resetContent() {
        // session 里还有原文和冻结边界，必须连同渲染器一起清掉，否则重播时偏移对不上。
        session.reset()
    }
}
