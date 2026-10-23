import CoreGraphics
import UIKit

/// 不需要视图实例的文本高度测量。
///
/// 块级高度原先只能靠 `UITextView.sizeThatFits` 算，于是「测一个块的高度」永远得先
/// 有一个活的 text view。这个约束一路传导到离屏测量，逼出了常驻测量 cell 与它那套
/// 复用池收支平衡的逻辑。这里改用一套**无视图的 TextKit 2 栈**直接量属性串，
/// 测高就变回纯值计算。
///
/// ## 为什么不是 CoreText
///
/// 最初按 CoreText（`CTFramesetterSuggestFrameSizeWithConstraints`）实现过一版，
/// 实测与视图相差 0~3pt，且误差随字号与行数变化而不是一个固定偏移——TextKit 对每个
/// line fragment 的取整规则 CoreText 复现不出来。靠经验公式去补这个差，等于把
/// TextKit 的内部实现反推一遍，换个字号或换个系统版本就可能失准。
///
/// 块视图内部的 `UITextView` 本来就由 TextKit 2 驱动，**用同一个引擎量，一致性是
/// 结构性的而不是巧合**。实测 36 组字号 × 行距 × 行数组合下与视图逐一相等。
///
/// ## 前提
///
/// 两个块视图都设了 `textContainerInset = .zero` 与 `lineFragmentPadding = 0`，
/// 这里的容器配置与之对齐。这两项配置一旦被改掉，这里就会悄悄算错——
/// `TextKitMeasurerParityTests` 守着这条。
///
/// ## 线程约定
///
/// 与 `AttributedCache` 一致：只在主线程调用。内部复用同一套 TextKit 对象以省掉
/// 每次测量的分配，因此不是线程安全的。
final class TextKitMeasurer {

    private let contentStorage = NSTextContentStorage()
    private let layoutManager = NSTextLayoutManager()
    private let container = NSTextContainer(size: CGSize(width: 0,
                                                         height: CGFloat.greatestFiniteMagnitude))

    /// 供测试断言实际测量次数，用来验证上层的高度缓存确实命中。
    private(set) var measureCountForTesting = 0

    init() {
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
    }

    /// 测量属性串在给定宽度下的排版高度。
    ///
    /// - Parameter width: `nil` 表示不限宽、不换行（代码块靠横向滚动查看，
    ///   与 `CodeBlockView` 里 `textContainer.size.width` 的设置保持一致）。
    func height(of attributed: NSAttributedString, width: CGFloat?) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        measureCountForTesting += 1

        container.size = CGSize(width: width.map { max(1, $0) } ?? .greatestFiniteMagnitude,
                                height: .greatestFiniteMagnitude)
        contentStorage.performEditingTransaction {
            contentStorage.textStorage?.setAttributedString(attributed)
        }
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        return ceil(layoutManager.usageBoundsForTextContainer.height)
    }

    /// 这种块类型的高度能否交给本测量器。
    ///
    /// 名单由 `TextKitMeasurerParityTests` 强制：名单内的类型必须与视图测量结果
    /// 完全一致，回归就红。名单外的类型由调用方回退到视图测量。
    static func canMeasure(_ kind: MarkdownBlockKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .blockQuote, .list, .table, .codeFence:
            // 代码块也在名单内：它不换行（宽度传 nil），正文之外的工具条与留白
            // 由 BlockMetrics.codeChromeHeight 单独加上，实测与视图一致。
            return true
        case .thematicBreak:
            // 分割线是固定高度的纯装饰，没有文本可量。
            return false
        }
    }
}
