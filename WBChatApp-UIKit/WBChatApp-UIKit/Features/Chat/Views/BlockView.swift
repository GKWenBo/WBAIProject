import UIKit

/// 一个块的视图。所有块视图都能自报高度，且能被复用池回收。
protocol BlockView: UIView {
    /// 这个视图实现类对应的复用池分类，唯一事实来源。
    /// 新增块视图类型时，编译器会强制要求声明它，`BlockViewPool.recycle`
    /// 直接读取它做归类，不再需要另外维护一份 `switch view { case is ... }`。
    static var viewKind: BlockViewKind { get }

    func configure(block: MarkdownBlock,
                   attributed: NSAttributedString,
                   renderer: AttributedRenderer)
    func heightThatFits(width: CGFloat) -> CGFloat
    func prepareForReuse()
}

enum BlockViewKind: Hashable {
    case text
    case code
    case divider

    static func kind(for blockKind: MarkdownBlockKind) -> BlockViewKind {
        switch blockKind {
        case .codeFence:     return .code
        case .thematicBreak: return .divider
        default:             return .text
        }
    }
}
