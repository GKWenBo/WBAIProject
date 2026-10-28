import UIKit

/// 一个块的视图。所有块视图都能自报高度，且能被复用池回收。
protocol BlockView: UIView {
    /// 这个视图实现类对应的复用池分类，唯一事实来源。
    /// 新增块视图类型时，编译器会强制要求声明它，`BlockViewPool.recycle`
    /// 直接读取它做归类，不再需要另外维护一份 `switch view { case is ... }`。
    static var viewKind: BlockViewKind { get }

    /// 绑定块内容；attributed 由上层渲染（并缓存）好后传入
    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer)
    func heightThatFits(width: CGFloat) -> CGFloat
    /// 回收到复用池前清理状态
    func prepareForReuse()
}

/// 块视图的复用分类：文本类块共用一种视图
enum BlockViewKind: Hashable {
    case text
    case code
    case divider

    /// Markdown 块类型 → 视图分类
    static func kind(for blockKind: MarkdownBlockKind) -> BlockViewKind {
        switch blockKind {
        case .codeFence:     return .code
        case .thematicBreak: return .divider
        default:             return .text
        }
    }
}
