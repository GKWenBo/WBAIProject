//
//  MarkdownBlockSplitter.swift
//  TextKitExample
//
//  案例 11：Markdown 流式渲染 —— 找出"开放尾块"的起点
//

import Foundation

/// 把流式到达的 Markdown 原文切成"已闭合的块"和"开放尾块"。
///
/// ## 为什么要切块
///
/// Markdown 上下文相关：`**加粗` 要等闭合才生效，围栏代码块打开后后面全是代码。
/// 新到的字符可能改变同一个块里旧文本的含义，但**不会**改变已经闭合的块。
/// 所以只要找到"最后一个已闭合块的末尾"，在它之前的内容就可以冻结（属性固定、不再解析），
/// 之后的内容（开放尾块）每次都从头重新解析。
///
/// ## 判定规则
///
/// - 块以**空行**分隔，但围栏代码块（``` / ~~~）内部的空行不算 —— 所以要带一个围栏状态机。
/// - 只有**以换行结尾的完整行**才参与判断。最后一行可能只到了一半
///   （比如刚来 `` ` `` 还不知道会不会变成 ```），它永远属于尾块。
///
/// ## 已知局限
///
/// 回溯型语法（Setext 标题 `标题\n===`、表格的分隔行、列表项的延续行）会让"已闭合"的判断过早。
/// 真实项目里可以把最后两个块都当作开放块来兜底；这里为了讲清主线没有处理。
/// 另外只识别 `\n` 换行，`\r\n` 需要调用方先归一化。
enum MarkdownBlockSplitter {

    /// 围栏标记：字符（`` ` `` 或 `~`）和连续个数（≥ 3）。
    struct Fence: Equatable {
        let character: Character
        let length: Int
    }

    /// 开放尾块在 `source` 中的起始偏移（UTF-16）。偏移之前的内容都是已闭合块。
    static func tailStart(in source: String) -> Int {
        var lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        // split 的最后一项是"最后一个换行之后的内容"，即尚未完整的行（可能为空），不参与判断。
        guard !lines.isEmpty else { return 0 }
        lines.removeLast()

        var offset = 0          // 当前行的起始偏移
        var boundary = 0        // 最近一个块边界：某个空行之后的位置
        var openFence: Fence?   // 非 nil 表示正处在围栏代码块内部

        for line in lines {
            offset += line.utf16.count + 1   // +1 是被 split 吃掉的 "\n"

            if let fence = openFence {
                // 围栏内部：一切都是代码，空行也不算边界，只等待闭合围栏。
                if isClosingFence(line, matching: fence) { openFence = nil }
                continue
            }
            if let fence = fence(of: line) {
                openFence = fence
            } else if line.allSatisfy(\.isWhitespace) {
                // 围栏之外的空行：它之前的块已经闭合。
                boundary = offset
            }
        }
        return boundary
    }

    // MARK: - 围栏识别（渲染器共用，保证两边对"哪里是代码块"的判断一致）

    /// 这一行是不是围栏开头。允许行首缩进，后面可以跟语言标记（```swift）。
    static func fence(of line: Substring) -> Fence? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == first }).count
        return length >= 3 ? Fence(character: first, length: length) : nil
    }

    /// 这一行是不是能闭合 `fence` 的围栏：同一种字符、不短于开头、后面不再有其他内容。
    static func isClosingFence(_ line: Substring, matching fence: Fence) -> Bool {
        guard let candidate = Self.fence(of: line),
              candidate.character == fence.character,
              candidate.length >= fence.length else { return false }
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.dropFirst(candidate.length).allSatisfy(\.isWhitespace)
    }
}
