import UIKit

/// 一次文本更新实际走的路径。供测试断言增量路径确实生效，而不是一直在回退。
enum TextUpdateKind: Equatable {
    /// 整体替换：首次配置、换绑内容、或前缀完全对不上
    case full
    /// 只替换了 `from` 之后的尾部
    case incremental(from: Int)
}

extension UITextView {

    /// 用 TextKit 2 的编辑事务把 `attributed` 增量应用到现有内容上。
    ///
    /// 直接 `attributedText = attributed` 会让整块排版失效，而流式期间未闭合块
    /// 每帧都要更新一次，块越长每帧越贵。这里改为只替换与旧内容发散的尾部，
    /// TextKit 2 的排版失效范围也就跟着收缩到尾部。
    ///
    /// **这不违反「禁止访问 layoutManager / textStorage」那条约束**：触发 TextKit 1
    /// 静默降级的是 `UITextView` 自己的 `layoutManager` 与 `textStorage` 两个属性，
    /// 而这里走的是 `textLayoutManager → textContentManager → textStorage`，
    /// 即 `NSTextContentStorage` 的后备存储，是 TextKit 2 的正规路径。
    /// `BlockViewTests` 里有哨兵断言盯着这件事。
    ///
    /// 拿不到 TextKit 2 的存储时（理论上只会发生在已经被降级的视图上）回退到整体
    /// 替换，行为与改动前一致。
    @discardableResult
    func applyIncrementally(_ attributed: NSAttributedString) -> TextUpdateKind {
        guard let contentStorage = textLayoutManager?.textContentManager as? NSTextContentStorage,
              let storage = contentStorage.textStorage else {
            attributedText = attributed
            return .full
        }

        let stable = AttributedPrefix.stableLength(storage, attributed)
        guard stable > 0 else {
            attributedText = attributed
            return .full
        }
        // 两边都没有超出稳定前缀的部分，内容完全没变，不必惊动排版。
        guard stable < storage.length || stable < attributed.length else {
            return .incremental(from: stable)
        }

        let staleRange = NSRange(location: stable, length: storage.length - stable)
        let tail = attributed.attributedSubstring(
            from: NSRange(location: stable, length: attributed.length - stable))
        contentStorage.performEditingTransaction {
            storage.replaceCharacters(in: staleRange, with: tail)
        }
        return .incremental(from: stable)
    }
}
