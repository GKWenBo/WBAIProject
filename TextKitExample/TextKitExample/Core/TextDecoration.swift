//
//  TextDecoration.swift
//  TextKitExample
//
//  案例 3：自定义背景装饰的描述
//

import UIKit

extension NSAttributedString.Key {
    /// 自定义背景装饰，value 为 `TextDecoration`。
    static let textDecoration = NSAttributedString.Key("TextKitExample.textDecoration")
}

/// 一段文本要画什么样的背景装饰。
///
/// 和 `.backgroundColor` 的区别：那个属性只会画紧贴字形的矩形，一行文字没排满就只有半行底色，
/// 也没有圆角和竖线。这里把"画成什么样"描述出来，交给 `DecoratingLayoutManager` 去画。
final class TextDecoration: NSObject {

    enum Style {
        /// 整行拉满容器宽度的底色，用于代码块。
        case fullWidthBackground
        /// 左侧竖线 + 浅底色，用于 Markdown 引用块。
        case leadingBar
        /// 贴着文字的圆角底色，跨行会自动拆成多段，用于行内高亮 / 标签。
        case roundedInline
    }

    let style: Style
    let color: UIColor
    let barColor: UIColor
    let cornerRadius: CGFloat
    let barWidth: CGFloat
    /// 底色相对文字行矩形上下各外扩多少。
    let verticalPadding: CGFloat

    init(style: Style,
         color: UIColor,
         barColor: UIColor = .clear,
         cornerRadius: CGFloat = 0,
         barWidth: CGFloat = 0,
         verticalPadding: CGFloat = 0) {
        self.style = style
        self.color = color
        self.barColor = barColor
        self.cornerRadius = cornerRadius
        self.barWidth = barWidth
        self.verticalPadding = verticalPadding
    }

    // MARK: - 预设

    static let codeBlock = TextDecoration(style: .fullWidthBackground,
                                          color: .secondarySystemBackground,
                                          cornerRadius: 8,
                                          verticalPadding: 6)

    static let blockQuoteBar = TextDecoration(style: .leadingBar,
                                              color: .tertiarySystemFill,
                                              barColor: .systemBlue,
                                              cornerRadius: 2,
                                              barWidth: 3,
                                              verticalPadding: 4)

    static let inlineHighlight = TextDecoration(style: .roundedInline,
                                                color: .systemYellow.withAlphaComponent(0.35),
                                                cornerRadius: 4,
                                                verticalPadding: 1)
}
