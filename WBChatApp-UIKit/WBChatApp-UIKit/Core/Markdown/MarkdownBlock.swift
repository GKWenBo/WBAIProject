import Foundation

/// 块类型，决定用哪种块视图渲染
enum MarkdownBlockKind: Equatable, Hashable, Sendable {
    case paragraph
    case heading(level: Int)
    case codeFence(language: String?)
    case list(ordered: Bool)
    case blockQuote
    case table
    case thematicBreak

    /// 这两类只占一行，看到完整行就能立刻闭合
    var sealsOnSingleLine: Bool {
        switch self {
        case .heading, .thematicBreak: return true
        default: return false
        }
    }
}

/// Markdown 的一个块级元素。
///
/// `isSealed` 为 true 表示后续文本不可能再改变它——这是整个增量渲染的地基：
/// 已闭合的块，其属性串与高度只会计算一次。
struct MarkdownBlock: Equatable, Hashable, Sendable {
    /// 在消息内单调递增，作为块的稳定身份
    let ordinal: Int
    let kind: MarkdownBlockKind
    /// 该块对应的 Markdown 源文本
    let rawText: String
    let isSealed: Bool

    /// 缓存键。刻意不含 ordinal，让内容相同的块跨消息共享缓存。
    var cacheKey: Int {
        var hasher = Hasher()
        hasher.combine(kind)
        hasher.combine(rawText)
        return hasher.finalize()
    }
}

/// 一次增量产生的变化。
struct BlockPatch: Equatable, Sendable {
    /// 本次新闭合的块，按 ordinal 顺序追加
    let newlySealed: [MarkdownBlock]
    /// 当前仍在书写的块，nil 表示流已收尾
    let open: MarkdownBlock?

    var isEmpty: Bool { newlySealed.isEmpty && open == nil }

    static let empty = BlockPatch(newlySealed: [], open: nil)
}
