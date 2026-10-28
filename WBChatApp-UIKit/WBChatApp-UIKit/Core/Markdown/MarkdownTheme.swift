import UIKit

/// Markdown 渲染的排版参数。集中在一处，方便调整与做深浅色适配。
struct MarkdownTheme: Sendable {

    /// 正文字体，跟随动态字号
    let bodyFont: UIFont
    /// 代码块与行内代码的等宽字体
    let monoFont: UIFont
    let textColor: UIColor
    /// 引用、列表符号等次要文字
    let secondaryColor: UIColor
    let linkColor: UIColor
    let codeTextColor: UIColor

    /// 块与块之间的垂直间距
    let blockSpacing: CGFloat
    /// 段内行间距
    let lineSpacing: CGFloat
    /// 每级列表的缩进
    let listIndent: CGFloat
    /// 引用块左侧竖条宽度
    let quoteBarWidth: CGFloat

    /// 标题字号在正文基础上按级别递增
    func headingFont(level: Int) -> UIFont {
        let size: CGFloat
        switch level {
        case 1: size = bodyFont.pointSize + 8
        case 2: size = bodyFont.pointSize + 5
        case 3: size = bodyFont.pointSize + 3
        default: size = bodyFont.pointSize + 1
        }
        return UIFont.systemFont(ofSize: size, weight: .semibold)
    }

    static let `default` = MarkdownTheme(
        bodyFont: UIFont.preferredFont(forTextStyle: .body),
        monoFont: UIFont.monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .callout).pointSize,
                                              weight: .regular),
        textColor: Theme.textPrimary,
        secondaryColor: Theme.textSecondary,
        linkColor: Theme.accent,
        codeTextColor: Theme.textPrimary,
        blockSpacing: 12,
        lineSpacing: 4,
        listIndent: 20,
        quoteBarWidth: 3
    )
}
