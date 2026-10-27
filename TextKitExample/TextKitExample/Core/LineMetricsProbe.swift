//
//  LineMetricsProbe.swift
//  TextKitExample
//
//  案例 8：精确的行信息与选区
//

import UIKit

/// 一行文本的排版信息。
struct TextLineMetrics {
    /// 第几行，从 0 开始。
    let index: Int
    /// 这一行对应的字符范围。
    let characterRange: NSRange
    /// 行片段矩形：含行距，上下相接、铺满容器宽度。
    let fragmentRect: CGRect
    /// 实际被文字占用的矩形：画选区高亮、做命中判断要用它。
    let usedRect: CGRect
    /// 基线相对容器原点的 y。
    let baseline: CGFloat
}

/// 从一段文本里取出逐行的排版信息。
///
/// 自己实现行号栏、选区高亮、查词浮层时都要用到这些数据。入口是
/// `NSLayoutManager.enumerateLineFragments(forGlyphRange:using:)`。
///
/// `fragmentRect` 和 `usedRect` 的区别值得记：前者是这一行"分到的地盘"，含行距、铺满宽度；
/// 后者才是文字真正占的地方。画行底色用前者，做点击命中和选区高亮用后者。
enum LineMetricsProbe {

    /// 逐行信息。
    static func lines(of text: NSAttributedString, width: CGFloat) -> [TextLineMetrics] {
        guard text.length > 0, width > 0 else { return [] }

        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        TextStyle.configure(container, width: width)

        // storage 必须活到取完行信息：它持有 layout manager，反向只是弱引用。
        return withExtendedLifetime(storage) {
            layoutManager.ensureLayout(for: container)
            return lines(in: layoutManager, container: container)
        }
    }

    /// 已有排版栈时直接取，避免重复排版。
    static func lines(in layoutManager: NSLayoutManager,
                      container: NSTextContainer) -> [TextLineMetrics] {
        var result: [TextLineMetrics] = []

        layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) {
            fragmentRect, usedRect, _, glyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange,
                                                              actualGlyphRange: nil)
            // location(forGlyphAt:) 给的是相对行片段原点的位置，y 分量就是基线。
            let baseline = fragmentRect.minY + layoutManager.location(forGlyphAt: glyphRange.location).y
            result.append(TextLineMetrics(index: result.count,
                                          characterRange: characterRange,
                                          fragmentRect: fragmentRect,
                                          usedRect: usedRect,
                                          baseline: baseline))
        }
        return result
    }

    /// 一段字符在排版里覆盖的所有矩形，跨行会拆成多段 —— 选区高亮就靠它。
    static func selectionRects(for characterRange: NSRange,
                               in layoutManager: NSLayoutManager,
                               container: NSTextContainer) -> [CGRect] {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange,
                                                  actualCharacterRange: nil)
        var rects: [CGRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
                                              withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                                              in: container) { rect, _ in
            rects.append(rect)
        }
        return rects
    }
}
