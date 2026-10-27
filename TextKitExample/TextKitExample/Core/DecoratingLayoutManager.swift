//
//  DecoratingLayoutManager.swift
//  TextKitExample
//
//  案例 3：代码块底色 / 引用竖线 / 行内圆角高亮
//

import UIKit

/// 按 `.textDecoration` 属性绘制自定义背景的 `NSLayoutManager`。
///
/// 入口是 `drawBackground(forGlyphRange:at:)` —— 它在字形之前绘制，所以画出来的底色
/// 天然在文字下面，不需要额外管层级。
///
/// 选 TextKit 1 是因为这里只需要重写一个方法。TextKit 2 的等价做法是实现
/// `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)`
/// 返回自定义的 `NSTextLayoutFragment` 子类，在它的 `draw(at:in:)` 里画 ——
/// 多一层对象，但能拿到更细的 fragment 信息。
///
/// ## 容易踩的坑
///
/// - 要用 `UITextView(usingTextLayoutManager: false)` 或手工三件套组装视图，否则
///   iOS 15 之后 `UITextView` 默认走 TextKit 2，这个子类根本不会被调用。
/// - `drawBackground` 给的是 **glyph** 范围，属性查询要先转成字符范围。
/// - 所有矩形都是容器坐标系，必须加上 `origin` 偏移。
final class DecoratingLayoutManager: NSLayoutManager {

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)

        guard let textStorage, let container = textContainers.first else { return }

        let characterRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        textStorage.enumerateAttribute(.textDecoration, in: characterRange) { value, range, _ in
            guard let decoration = value as? TextDecoration else { return }
            draw(decoration, characterRange: range, in: container, at: origin)
        }
    }

    // MARK: - 绘制

    private func draw(_ decoration: TextDecoration,
                      characterRange: NSRange,
                      in container: NSTextContainer,
                      at origin: CGPoint) {
        let rects = enclosingRects(forCharacterRange: characterRange, in: container)
        guard !rects.isEmpty else { return }

        switch decoration.style {
        case .fullWidthBackground:
            guard var box = union(of: rects) else { return }
            // 容器宽度可能是「不限宽」，那种情况退回用文字自身的宽度。
            box.origin.x = 0
            box.size.width = container.size.width.isFinite ? container.size.width : box.width
            fill(box.expanded(by: decoration.verticalPadding).offsetBy(dx: origin.x, dy: origin.y),
                 radius: decoration.cornerRadius,
                 color: decoration.color)

        case .leadingBar:
            guard let box = union(of: rects) else { return }
            var background = box
            background.origin.x = 0
            background.size.width = container.size.width.isFinite ? container.size.width : box.width
            background = background.expanded(by: decoration.verticalPadding)
                .offsetBy(dx: origin.x, dy: origin.y)
            fill(background, radius: decoration.cornerRadius, color: decoration.color)

            let bar = CGRect(x: background.minX,
                             y: background.minY,
                             width: decoration.barWidth,
                             height: background.height)
            fill(bar, radius: decoration.barWidth / 2, color: decoration.barColor)

        case .roundedInline:
            // 跨行的高亮逐段画，才不会连成一个把整块包住的大矩形。
            for rect in rects {
                fill(rect.expanded(by: decoration.verticalPadding).offsetBy(dx: origin.x, dy: origin.y),
                     radius: decoration.cornerRadius,
                     color: decoration.color)
            }
        }
    }

    private func fill(_ rect: CGRect, radius: CGFloat, color: UIColor) {
        guard color != .clear, rect.width > 0, rect.height > 0 else { return }
        color.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
    }

    // MARK: - 取矩形

    /// 一段字符覆盖的所有矩形。跨行会返回多个，和选区高亮用的是同一套数据。
    private func enclosingRects(forCharacterRange characterRange: NSRange,
                                in container: NSTextContainer) -> [CGRect] {
        let glyphRange = glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var rects: [CGRect] = []
        enumerateEnclosingRects(forGlyphRange: glyphRange,
                                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                in: container) { rect, _ in
            rects.append(rect)
        }
        return rects
    }

    private func union(of rects: [CGRect]) -> CGRect? {
        rects.dropFirst().reduce(rects.first) { $0?.union($1) }
    }
}

private extension CGRect {
    /// 上下各外扩 `padding`。
    func expanded(by padding: CGFloat) -> CGRect {
        insetBy(dx: 0, dy: -padding)
    }
}
