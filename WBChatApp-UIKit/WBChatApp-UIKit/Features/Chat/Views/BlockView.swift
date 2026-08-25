import UIKit

/// 一个块的视图。所有块视图都能自报高度，且能被复用池回收。
protocol BlockView: UIView {
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
