//
//  TextKit1IncrementalRenderer.swift
//  TextKitExample
//
//  案例 9：TextKit 1 的增量更新
//

import UIKit

/// 基于 TextKit 1（`NSTextStorage` + `NSLayoutManager`）的增量文本渲染器。
///
/// ## 增量是怎么发生的
///
/// 往 `NSTextStorage` 末尾 `replaceCharacters(in:with:)` 时，storage 在 `endEditing()`
/// 里调用 layout manager 的 `processEditing(for:edited:range:changeInLength:invalidatedRange:)`，
/// 告诉它"哪段字符的排版失效了"。layout manager 只重排这段及其后面的内容，
/// 前面已经排好的部分原样保留。
///
/// ## 怎么看出它是增量的
///
/// 重写上面那个方法，把 `invalidatedRange` 记下来：追加时它恰好就是新追加的那几个字符，
/// 全量替换时从 0 开始覆盖全文。总长度减去这个起点，就是这次要重排的字符数。
/// 实测 395 字符的文本，追加一块只失效 3 个字符、重排 1 行；全量替换是 395 字符、23 行。
///
/// 起初试过用 `firstUnlaidCharacterIndex()` 判断失效起点，实测 iOS 27 上 `endEditing()`
/// 返回后它已经等于全文长度，拿不到中间状态，所以改用这个由 storage 直接通知的钩子。
///
/// ## 容易踩的坑
///
/// - 多处修改要包在 `beginEditing()` / `endEditing()` 里，否则每改一处就通知一次。
/// - 关掉了 `allowsNonContiguousLayout`：打开后排版可以跳着做，"从失效起点排到文末"
///   的统计口径就不成立了。超长文本的真实项目里可以打开它换取性能。
final class TextKit1IncrementalRenderer: IncrementalTextRenderer {

    let textStorage = NSTextStorage()
    private let trackingLayoutManager = InvalidationTrackingLayoutManager()
    var layoutManager: NSLayoutManager { trackingLayoutManager }
    let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

    init() {
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.allowsNonContiguousLayout = false
        textContainer.lineFragmentPadding = 0
    }

    var string: String { textStorage.string }

    // MARK: - 更新

    func append(_ text: NSAttributedString) -> IncrementalUpdateReport {
        update {
            let end = NSRange(location: textStorage.length, length: 0)
            textStorage.replaceCharacters(in: end, with: text)
        }
    }

    func replaceTail(from location: Int, with text: NSAttributedString) -> IncrementalUpdateReport {
        update {
            // 收敛起点，防止调用方传入过期偏移（比如 reset 之后）导致越界崩溃。
            let start = max(0, min(location, textStorage.length))
            // 替换范围从"块起点"一直到文末，而不是只替换新增字符：
            // 块内任何语法变化（段落变列表、`**` 闭合、围栏打开）都能整体重做，属性不会残缺。
            // storage 通知的失效范围从 start 开始，layout manager 只重排这一段，之前的行不动。
            let tail = NSRange(location: start, length: textStorage.length - start)
            textStorage.replaceCharacters(in: tail, with: text)
        }
    }

    func replaceAll(with text: NSAttributedString) -> IncrementalUpdateReport {
        update {
            textStorage.setAttributedString(text)
        }
    }

    func reset() {
        textStorage.setAttributedString(NSAttributedString())
    }

    func makeTextView() -> UITextView {
        // 传入自己组装的容器 → UITextView 使用这套 TextKit 1 栈。
        textContainer.widthTracksTextView = true
        let textView = UITextView(frame: .zero, textContainer: textContainer)
        // UITextView 接管后可能改动这个开关，这里再确认一次，保证统计口径不变。
        layoutManager.allowsNonContiguousLayout = false
        return textView
    }

    // MARK: - 统计

    /// 执行一次编辑，并统计随后的排版工作量。
    private func update(_ edit: () -> Void) -> IncrementalUpdateReport {
        let start = CFAbsoluteTimeGetCurrent()

        trackingLayoutManager.lastInvalidatedRange = nil
        textStorage.beginEditing()
        edit()
        textStorage.endEditing()

        // storage 通知的失效起点；没有收到通知说明什么都没变。
        let invalidatedFrom = min(trackingLayoutManager.lastInvalidatedRange?.location ?? textStorage.length,
                                  textStorage.length)

        // 立刻把版排完，统计才能拿到"这次重排了几行"；屏幕上的 text view 也正好直接用。
        layoutManager.ensureLayout(for: textContainer)
        let duration = CFAbsoluteTimeGetCurrent() - start

        return IncrementalUpdateReport(totalLength: textStorage.length,
                                       relaidCharacters: textStorage.length - invalidatedFrom,
                                       relaidUnits: lineCount(fromCharacter: invalidatedFrom),
                                       unitName: "行",
                                       duration: duration)
    }

    /// 从某个字符开始到文末一共有几行。
    private func lineCount(fromCharacter location: Int) -> Int {
        guard location < textStorage.length else { return 0 }

        let characterRange = NSRange(location: location, length: textStorage.length - location)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var count = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
            count += 1
        }
        return count
    }
}

// MARK: - 记录失效范围

/// 只做一件事：把 text storage 通知过来的失效范围记下来。
private final class InvalidationTrackingLayoutManager: NSLayoutManager {

    /// 最近一次编辑让排版失效的字符范围。一次编辑事务里可能收到多次通知，取并集。
    var lastInvalidatedRange: NSRange?

    override func processEditing(for textStorage: NSTextStorage,
                                 edited editMask: NSTextStorage.EditActions,
                                 range newCharRange: NSRange,
                                 changeInLength delta: Int,
                                 invalidatedRange invalidatedCharRange: NSRange) {
        lastInvalidatedRange = lastInvalidatedRange.map { NSUnionRange($0, invalidatedCharRange) }
            ?? invalidatedCharRange
        super.processEditing(for: textStorage,
                             edited: editMask,
                             range: newCharRange,
                             changeInLength: delta,
                             invalidatedRange: invalidatedCharRange)
    }
}
