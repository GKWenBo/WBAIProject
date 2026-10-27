//
//  TextStyle.swift
//  TextKitExample
//

import UIKit

/// 全工程共用的文本样式，以及 TextKit 容器的配置约定。
///
/// 为什么要把容器配置收口到一个地方：离屏测量用的 TextKit 栈和真正显示文本的视图栈
/// 是两套对象，只有参数完全一致，算出来的高度才等于实际排版的高度。最容易漏的是
/// `lineFragmentPadding`（默认 5）和 `UITextView.textContainerInset`（默认上下 8、
/// 左右 0），只改一边就会出现"列表行底部多一截空白"或"最后一行被切掉"这类偏差。
enum TextStyle {

    // MARK: - 字体与间距

    static let bodyFontSize: CGFloat = 16
    static let codeFontSize: CGFloat = 13
    static let lineSpacing: CGFloat = 6

    static let bodyFont = UIFont.systemFont(ofSize: bodyFontSize)
    static let codeFont = UIFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

    // MARK: - 段落样式

    static func paragraphStyle(lineSpacing: CGFloat = Self.lineSpacing,
                               alignment: NSTextAlignment = .natural,
                               lineBreakMode: NSLineBreakMode = .byWordWrapping) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.alignment = alignment
        style.lineBreakMode = lineBreakMode
        return style
    }

    // MARK: - 常用属性组合

    static var body: [NSAttributedString.Key: Any] {
        [.font: bodyFont,
         .foregroundColor: UIColor.label,
         .paragraphStyle: paragraphStyle()]
    }

    static var code: [NSAttributedString.Key: Any] {
        [.font: codeFont,
         .foregroundColor: UIColor.label,
         .paragraphStyle: paragraphStyle(lineSpacing: 3)]
    }

    static var quote: [NSAttributedString.Key: Any] {
        [.font: bodyFont,
         .foregroundColor: UIColor.secondaryLabel,
         .paragraphStyle: paragraphStyle()]
    }

    // MARK: - 容器配置约定

    /// 排版容器的统一配置。测量栈与视图栈都调它，两边才对得上。
    ///
    /// - Parameter width: `nil` 表示不限宽、不换行（代码块靠横向滚动查看时用）。
    /// 只操作传入的容器、不碰任何全局状态，因此声明为 `nonisolated`，后台测高线程可直接调用。
    nonisolated static func configure(_ container: NSTextContainer,
                          width: CGFloat?,
                          maximumNumberOfLines: Int = 0,
                          lineBreakMode: NSLineBreakMode = .byWordWrapping) {
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = maximumNumberOfLines
        container.lineBreakMode = lineBreakMode
        container.size = CGSize(width: width.map { max(1, $0) } ?? .greatestFiniteMagnitude,
                                height: .greatestFiniteMagnitude)
    }

    /// `UITextView` 侧的同一套约定。
    static func configure(_ textView: UITextView) {
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.backgroundColor = .clear
    }
}
