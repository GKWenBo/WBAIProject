//
//  TextKit2IncrementalRenderer.swift
//  TextKitExample
//
//  案例 10：TextKit 2 的增量更新
//

import UIKit

/// 基于 TextKit 2（`NSTextContentStorage` + `NSTextLayoutManager`）的增量文本渲染器。
///
/// ## 增量是怎么发生的
///
/// TextKit 2 把文本拆成一个个**段落**（`NSTextParagraph`），每段对应一个排版结果
/// `NSTextLayoutFragment`，并按段缓存。往末尾追加时只有最后一段的内容变了，
/// 只有它会被重新生成 fragment；前面的段落连同排版结果原样复用。
/// 这也是 TextKit 2 适合流式长文的根本原因：增量粒度天然就是段落。
///
/// ## 怎么看出它是增量的
///
/// 实现 `NSTextLayoutManagerDelegate` 的 `textLayoutManager(_:textLayoutFragmentFor:in:)`，
/// 每新建一个 fragment 它就会被调一次。统计一次更新前后被调了几次、这些 fragment
/// 覆盖了多少字符，就是这次的真实重排量。
///
/// ## 容易踩的坑
///
/// - 编辑必须放进 `performEditingTransaction`，否则 layout manager 收不到成组的变更通知。
/// - 直接改 `textView.text` / `attributedText` 等同于全量替换，所有段落都会重建。
final class TextKit2IncrementalRenderer: NSObject, IncrementalTextRenderer {

    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

    // delegate 回调里累加，统计时取前后差值。
    private var createdFragments = 0
    private var createdCharacters = 0

    override init() {
        super.init()
        textContainer.lineFragmentPadding = 0
        layoutManager.textContainer = textContainer
        layoutManager.delegate = self
        contentStorage.addTextLayoutManager(layoutManager)
    }

    var string: String { contentStorage.textStorage?.string ?? "" }

    private var length: Int { contentStorage.textStorage?.length ?? 0 }

    // MARK: - 更新

    func append(_ text: NSAttributedString) -> IncrementalUpdateReport {
        update { storage in
            storage.append(text)
        }
    }

    func replaceTail(from location: Int, with text: NSAttributedString) -> IncrementalUpdateReport {
        update { storage in
            // 收敛起点，防止调用方传入过期偏移导致越界崩溃。
            let start = max(0, min(location, storage.length))
            // 从"块起点"替换到文末，整个尾块用新渲染的富文本重建：
            // 段落样式取自段落首字符，起点正好落在块的开头，所以首字符的样式一定是新的，
            // 不会沿用上一版尾块的属性。
            // TextKit 2 以段落为缓存单位：起点之前的段落内容和位置都没变，fragment 原样复用；
            // 只有尾块覆盖的那几段会重新走 delegate 生成 fragment。
            let tail = NSRange(location: start, length: storage.length - start)
            storage.replaceCharacters(in: tail, with: text)
        }
    }

    func replaceAll(with text: NSAttributedString) -> IncrementalUpdateReport {
        update { storage in
            storage.setAttributedString(text)
        }
    }

    func reset() {
        contentStorage.performEditingTransaction {
            contentStorage.textStorage?.setAttributedString(NSAttributedString())
        }
    }

    func makeTextView() -> UITextView {
        // 容器已经挂在 NSTextLayoutManager 上 → UITextView 使用这套 TextKit 2 栈。
        textContainer.widthTracksTextView = true
        return UITextView(frame: .zero, textContainer: textContainer)
    }

    // MARK: - 统计

    private func update(_ edit: (NSTextStorage) -> Void) -> IncrementalUpdateReport {
        let fragmentsBefore = createdFragments
        let charactersBefore = createdCharacters
        let start = CFAbsoluteTimeGetCurrent()

        contentStorage.performEditingTransaction {
            if let storage = contentStorage.textStorage {
                edit(storage)
            }
        }
        // 立刻排完整篇：已缓存的段落直接复用，只有被改动的段落会走到 delegate。
        // 真实项目里不必这么做，UITextView 会按视口按需排版。
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        let duration = CFAbsoluteTimeGetCurrent() - start

        return IncrementalUpdateReport(totalLength: length,
                                       relaidCharacters: createdCharacters - charactersBefore,
                                       relaidUnits: createdFragments - fragmentsBefore,
                                       unitName: "段",
                                       duration: duration)
    }
}

// MARK: - NSTextLayoutManagerDelegate

extension TextKit2IncrementalRenderer: NSTextLayoutManagerDelegate {

    /// 每新建一个 layout fragment 调一次。这里不定制 fragment，只做计数。
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager,
                           textLayoutFragmentFor location: NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        createdFragments += 1
        if let range = textElement.elementRange,
           let contentManager = textLayoutManager.textContentManager {
            createdCharacters += contentManager.offset(from: range.location, to: range.endLocation)
        }
        return NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
