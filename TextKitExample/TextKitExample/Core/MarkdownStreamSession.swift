//
//  MarkdownStreamSession.swift
//  TextKitExample
//
//  案例 11：Markdown 流式渲染 —— "冻结已闭合块 + 重渲染尾块"的调度
//

import Foundation

/// 把流式到达的 Markdown 原文增量渲染进一个 `IncrementalTextRenderer`。
///
/// ## 核心思路
///
/// 1. 用 `MarkdownBlockSplitter` 找出开放尾块的起点，之前的块都已闭合，渲染结果固定不变（冻结）。
/// 2. 每来一块新文本，只把**尾块的完整原文**重新渲染，
///    再用 `replaceTail` 替换掉 storage 里从尾块起点到文末的内容。
/// 3. 尾块闭合后，把冻结边界向后推。
///
/// ## 两套偏移
///
/// 原文和渲染结果不等长（`#`、围栏行、`**` 渲染后都消失了），所以要分别记录：
/// - `frozenSourceLength`：原文里已冻结部分的长度，用来从原文切出尾块；
/// - `frozenRenderedLength`：storage 里已冻结部分的长度，用来告诉 `replaceTail` 从哪里开始替换。
///
/// 两个值总是同步推进：冻结某段原文的同时，记下它渲染出来的长度。
final class MarkdownStreamSession {

    private let renderer: IncrementalTextRenderer

    /// 到目前为止收到的全部原文。
    private(set) var source = ""

    private var frozenSourceLength = 0
    private var frozenRenderedLength = 0

    init(renderer: IncrementalTextRenderer) {
        self.renderer = renderer
    }

    /// 收到新的一块原文，增量更新。
    func append(_ chunk: String) -> IncrementalUpdateReport {
        source += chunk
        let nsSource = source as NSString

        // 冻结边界只会往后走：已闭合块里的空行和围栏状态不会被后续文本改写。
        // max 是防御，保证即使切分器将来对某些输入判断回退，也不会把已冻结的内容重新替换成别的东西。
        let tailStart = max(MarkdownBlockSplitter.tailStart(in: source), frozenSourceLength)

        let replacement = NSMutableAttributedString()

        // 本次新闭合的块：渲染一次，之后冻结。
        var newlyFrozenRenderedLength = 0
        if tailStart > frozenSourceLength {
            let closed = nsSource.substring(with: NSRange(location: frozenSourceLength,
                                                          length: tailStart - frozenSourceLength))
            let rendered = MarkdownRenderer.render(closed)
            replacement.append(rendered)
            newlyFrozenRenderedLength = rendered.length
        }

        // 开放尾块：每次都从块起点的完整原文重新渲染，所以块内语法怎么变，属性都是完整的。
        replacement.append(MarkdownRenderer.render(nsSource.substring(from: tailStart)))

        // 一次编辑完成"新冻结块 + 新尾块"的替换：起点是旧的冻结边界，之前的内容完全不动。
        let report = renderer.replaceTail(from: frozenRenderedLength, with: replacement)

        frozenSourceLength = tailStart
        frozenRenderedLength += newlyFrozenRenderedLength
        return report
    }

    /// 对照组：每次都把"到目前为止的全部原文"渲染一遍再整体替换。
    func replaceAll(with fullSource: String) -> IncrementalUpdateReport {
        source = fullSource
        // 冻结边界不再有意义，归零；切回增量模式前调用方应该先 reset。
        frozenSourceLength = 0
        frozenRenderedLength = 0
        return renderer.replaceAll(with: MarkdownRenderer.render(fullSource))
    }

    func reset() {
        source = ""
        frozenSourceLength = 0
        frozenRenderedLength = 0
        renderer.reset()
    }
}
