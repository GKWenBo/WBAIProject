import UIKit

/// Markdown 渲染的排版参数。集中在一处，方便调整与做深浅色适配。
struct MarkdownTheme: Sendable {

    let bodyFont: UIFont
    let monoFont: UIFont
    let textColor: UIColor
    let secondaryColor: UIColor
    let linkColor: UIColor
    let codeTextColor: UIColor

    /// 块与块之间的垂直间距
    let blockSpacing: CGFloat
    let lineSpacing: CGFloat
    let listIndent: CGFloat
    let quoteBarWidth: CGFloat

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
