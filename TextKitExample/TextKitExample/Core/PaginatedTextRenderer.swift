//
//  PaginatedTextRenderer.swift
//  TextKitExample
//
//  案例 5：分页 / 多栏（阅读器）
//

import UIKit

/// 把一段长文切成若干页（或若干栏）。
///
/// 原理是 TextKit 1 的一个独有能力：**一个 `NSLayoutManager` 可以挂多个
/// `NSTextContainer`**，文字排满一个会自动流到下一个。每个容器对应一页或一栏，
/// 配上多个 `UITextView`（或自绘视图）就是阅读器分页。
///
/// TextKit 2 的 `NSTextLayoutManager` 只支持单个容器，所以这个场景只能用 TextKit 1。
///
/// ## 容易踩的坑
///
/// - 容器要一个一个加：加完必须触发排版，才知道这一页装了多少、还剩多少。
/// - 容器尺寸必须是确定值，`greatestFiniteMagnitude` 会让所有文字都挤进第一页。
final class PaginatedTextRenderer {

    let textStorage = NSTextStorage()

    /// 所有页共用这一个 layout manager，页视图直接拿它绘制。
    ///
    /// 不要把容器交给 `UITextView(frame:textContainer:)`：text view 会按自己的 bounds 和
    /// `textContainerInset` 回写容器尺寸并触发重排，分页结果会在视图挂上去之后悄悄变化，
    /// 表现为相邻两页内容重叠。页面自绘就没有这个问题。
    let layoutManager = NSLayoutManager()

    /// 每页一个容器，顺序即页序。
    private(set) var containers: [NSTextContainer] = []

    /// 页数上限，防止页面尺寸过小时无限加容器。
    private let pageLimit: Int

    init(text: NSAttributedString, pageLimit: Int = 200) {
        self.pageLimit = pageLimit
        textStorage.addLayoutManager(layoutManager)
        textStorage.setAttributedString(text)
    }

    /// 按页面尺寸重新分页。
    /// - Returns: 分出的页数。
    @discardableResult
    func paginate(pageSize: CGSize) -> Int {
        guard pageSize.width > 0, pageSize.height > 0, textStorage.length > 0 else {
            removeAllContainers()
            return 0
        }

        removeAllContainers()
        let totalGlyphs = layoutManager.numberOfGlyphs

        while containers.count < pageLimit {
            let container = NSTextContainer(size: pageSize)
            container.lineFragmentPadding = 0
            container.maximumNumberOfLines = 0
            layoutManager.addTextContainer(container)
            containers.append(container)

            // 加完就排一次版，才能知道排到哪儿了。
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)

            // 这一页一个字都装不下（容器太小），停下来避免空转。
            if glyphRange.length == 0 && containers.count > 1 {
                layoutManager.removeTextContainer(at: containers.count - 1)
                containers.removeLast()
                break
            }
            if NSMaxRange(glyphRange) >= totalGlyphs { break }
        }
        return containers.count
    }

    /// 某一页对应的字符范围。
    func characterRange(forPage index: Int) -> NSRange {
        guard containers.indices.contains(index) else { return NSRange(location: 0, length: 0) }
        let glyphRange = layoutManager.glyphRange(for: containers[index])
        return layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
    }

    private func removeAllContainers() {
        while !containers.isEmpty {
            layoutManager.removeTextContainer(at: containers.count - 1)
            containers.removeLast()
        }
    }
}
