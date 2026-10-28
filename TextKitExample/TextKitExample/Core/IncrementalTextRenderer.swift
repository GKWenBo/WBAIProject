//
//  IncrementalTextRenderer.swift
//  TextKitExample
//
//  案例 9 / 10：增量更新文本的公共接口
//

import UIKit

/// 一次文本更新之后，排版引擎实际重做了多少工作。
struct IncrementalUpdateReport {
    /// 更新后的文本总长度（UTF-16）。
    let totalLength: Int
    /// 这次需要重新排版的字符数。增量追加时应远小于总长度，全量替换时等于总长度。
    let relaidCharacters: Int
    /// 这次重新生成的排版单元数：TextKit 1 是行（line fragment），TextKit 2 是段（layout fragment）。
    let relaidUnits: Int
    /// 排版单元的叫法，用于展示。
    let unitName: String
    /// 编辑 + 排版的耗时。
    let duration: TimeInterval
}

/// 支持"追加"和"全量替换"两种更新方式的文本渲染器。
///
/// 流式输出（AI 对话、日志、聊天）的关键是**只追加、不重设**：
/// 每块都 `textView.text = 全部内容` 会让排版引擎从头排一遍，总代价 O(n²)；
/// 往 text storage 末尾追加，引擎只重排受影响的尾部，总代价 O(n)。
///
/// 两个实现分别对应 TextKit 1 和 TextKit 2，对外接口一致，便于在同一个页面里对比。
protocol IncrementalTextRenderer: AnyObject {

    /// 当前全文。
    var string: String { get }

    /// 往末尾追加一块文本。
    func append(_ text: NSAttributedString) -> IncrementalUpdateReport

    /// 把 `location` 之后的内容（"开放尾块"）整体替换成新渲染的结果。
    ///
    /// 这是 Markdown 流式渲染的关键操作。Markdown 语法上下文相关：`**加粗` 要等到闭合才生效，
    /// 围栏代码块打开后后面全是代码，段落也可能中途变成列表。所以尾块每次都要
    /// **从块起点把原文整体重新解析、重新渲染**，再替换掉 storage 里从块起点到文末的内容，
    /// 而不是 `append` 一个只带增量的片段（那样属性会不完整，也会继承上一个字符的属性）。
    ///
    /// - Parameters:
    ///   - location: 尾块在全文中的起始 UTF-16 偏移，即最后一个已冻结块的末尾。
    ///     超出范围会被收敛到 `0...length`。
    ///   - text: 尾块完整原文渲染出的富文本，段落首字符必须带正确的段落样式。
    ///
    /// `location` 之前已闭合的块不会被触碰，排版结果原样复用。
    func replaceTail(from location: Int, with text: NSAttributedString) -> IncrementalUpdateReport

    /// 用新内容整体替换。流式场景里的反面教材，留作对照。
    func replaceAll(with text: NSAttributedString) -> IncrementalUpdateReport

    /// 清空。
    func reset()

    /// 生成一个挂在这套排版栈上的 `UITextView`。
    ///
    /// 由渲染器来建视图，是因为 TextKit 1 / 2 的视图组装方式不同，调用方不必关心。
    func makeTextView() -> UITextView
}
