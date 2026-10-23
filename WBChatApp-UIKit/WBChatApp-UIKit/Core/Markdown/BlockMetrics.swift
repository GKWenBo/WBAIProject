import CoreGraphics

/// 块级排版的尺寸常量与派生算式，单一事实来源。
///
/// 这些数字此前散在各个块视图内部，同一个算式往往在「配置约束」和「算高度」两处
/// 各写一遍。离屏测量要用到完全相同的可用宽度，一旦两边各自漂移，测出来的高度就
/// 和实际渲染对不上，所以收口到这里。
enum BlockMetrics {

    /// 引用块左侧竖条与正文之间的间隔
    static let quoteBarGap: CGFloat = 8

    /// 代码块顶部「语言 + 复制」工具条的高度
    static let codeHeaderHeight: CGFloat = 32

    /// 代码块内容四周的留白
    static let codeContentInset: CGFloat = 12

    /// 代码块除正文以外占掉的高度：顶部工具条 + 底部留白
    static let codeChromeHeight: CGFloat = codeHeaderHeight + codeContentInset

    /// 正文相对块左边缘的缩进。引用块要给左侧竖条让位。
    static func textLeadingInset(for kind: MarkdownBlockKind) -> CGFloat {
        kind == .blockQuote ? MarkdownTheme.default.quoteBarWidth + quoteBarGap : 0
    }

    /// 给定块宽度下，正文实际可用的排版宽度。
    ///
    /// 代码块不走这里——它不换行，靠横向滚动查看。
    static func textContentWidth(for kind: MarkdownBlockKind, in width: CGFloat) -> CGFloat {
        max(1, width - textLeadingInset(for: kind))
    }

    /// 块自身装饰占掉的高度，不含正文。
    static func chromeHeight(for kind: MarkdownBlockKind) -> CGFloat {
        if case .codeFence = kind { return codeChromeHeight }
        return 0
    }
}
