//
//  TruncationProbe.swift
//  TextKitExample
//
//  案例 7：截断与「…展开」
//

import UIKit

/// 判断文本在限定行数下会不会被截断、截在哪个字符。
///
/// `UILabel` 只告诉你"放不下我就打点"，不告诉你打在哪。想在末尾精确地拼一个"展开"按钮，
/// 就得自己问排版引擎：`truncatedGlyphRange(inLineFragmentForGlyphAt:)` 返回最后一行
/// 被吃掉的那段字形范围，换成字符索引就是该截的位置。
///
/// TextKit 2 目前没有等价查询，所以这里用 TextKit 1。
enum TruncationProbe {

    struct Result {
        /// 是否被截断。
        let isTruncated: Bool
        /// 限定行数内实际排了几行。
        let lineCount: Int
        /// 截断处的字符索引；没截断时为 `nil`。
        let truncationCharacterIndex: Int?
    }

    /// 探测文本在给定宽度、给定最大行数下的截断情况。
    static func probe(_ text: NSAttributedString,
                      width: CGFloat,
                      maxLines: Int) -> Result {
        guard text.length > 0, width > 0 else {
            return Result(isTruncated: false, lineCount: 0, truncationCharacterIndex: nil)
        }

        let (storage, layoutManager, container) = makeStack(text, width: width, maxLines: maxLines)

        // storage 必须活到测量结束：NSTextStorage 持有 layout manager，反向只是弱引用，
        // 一旦它提前释放，layout manager 就没有文本可排，结果会变成"0 行、没截断"。
        return withExtendedLifetime(storage) {
            layoutManager.ensureLayout(for: container)

            var lineCount = 0
            var lastLineGlyphLocation = 0
            layoutManager.enumerateLineFragments(forGlyphRange: layoutManager.glyphRange(for: container)) {
                _, _, _, glyphRange, _ in
                lineCount += 1
                lastLineGlyphLocation = glyphRange.location
            }
            guard lineCount > 0 else {
                return Result(isTruncated: false, lineCount: 0, truncationCharacterIndex: nil)
            }

            let truncated = layoutManager.truncatedGlyphRange(inLineFragmentForGlyphAt: lastLineGlyphLocation)
            guard truncated.location != NSNotFound else {
                return Result(isTruncated: false, lineCount: lineCount, truncationCharacterIndex: nil)
            }
            return Result(isTruncated: true,
                          lineCount: lineCount,
                          truncationCharacterIndex: layoutManager.characterIndexForGlyph(at: truncated.location))
        }
    }

    /// 生成"截断 + 尾巴"的收起态文本，保证拼上尾巴后仍然不超过 `maxLines` 行。
    ///
    /// 直接截到 `truncationCharacterIndex` 再拼"… 展开"通常会多出一行 —— 尾巴本身也占宽度。
    /// 所以从该位置往回退，退到拼上尾巴恰好放得下为止。实测只需要退几个字符。
    ///
    /// - Returns: 不需要截断时原样返回。
    static func collapsed(_ text: NSAttributedString,
                          suffix: NSAttributedString,
                          width: CGFloat,
                          maxLines: Int,
                          maxBackoff: Int = 64) -> NSAttributedString {
        let result = probe(text, width: width, maxLines: maxLines)
        guard result.isTruncated, var cut = result.truncationCharacterIndex else { return text }

        let lowerBound = max(0, cut - maxBackoff)
        while cut > lowerBound {
            let candidate = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: cut)))
            candidate.append(suffix)
            if !probe(candidate, width: width, maxLines: maxLines).isTruncated {
                return candidate
            }
            cut -= 1
        }

        // 退到上限还放不下（尾巴太长或宽度太窄），退回最保守的结果。
        let fallback = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: lowerBound)))
        fallback.append(suffix)
        return fallback
    }

    // MARK: - 私有

    /// 一套只用于测量的 TextKit 1 栈，不挂视图。storage 要一并返回，由调用方保活。
    private static func makeStack(_ text: NSAttributedString,
                                  width: CGFloat,
                                  maxLines: Int) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage(attributedString: text)
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer()

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        // 截断是容器的行为：必须同时设最大行数和 byTruncatingTail，缺一个都查不到截断范围。
        TextStyle.configure(container,
                            width: width,
                            maximumNumberOfLines: maxLines,
                            lineBreakMode: .byTruncatingTail)
        return (storage, layoutManager, container)
    }
}
