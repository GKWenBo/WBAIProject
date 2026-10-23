import Foundation

/// 求两个属性串「字符与属性都完全相同」的最长前缀。
///
/// 这是 TextKit 2 增量追加排版的正确性基础。**不能靠 Markdown 语义猜「哪一段已经稳定」**——
/// 行内语法会追溯改写前面的渲染结果：`前**粗` 再追加两个星号变成 `前**粗**` 时，
/// 原本当作普通文字的那几个字符会变成加粗，前缀的属性跟着一起变。
///
/// 所以只比对渲染结果本身：前缀一致就原样保留，不一致就多替换一些。正确性由构造
/// 保证——最坏情况退化成全量替换，不存在「以为稳定其实不稳定」的中间态。
///
/// 代价可控的关键在于**属性 run 的数量很少**（一个段落通常 1~10 个 run），所以属性
/// 比对是 O(run 数) 而不是 O(字符数)；字符前缀比对是 O(前缀长度)，与「本来就要把
/// 整个属性串构建出来」同阶，没有引入新的数量级。
enum AttributedPrefix {

    /// 返回 `old` 与 `new` 字符与属性都相同的最长前缀长度，单位是 UTF-16 偏移，
    /// 可直接用于 `NSRange`。
    ///
    /// 返回值保证**不落在同一个字位簇内部**：从代理对中间切开再替换会产生乱码，
    /// 从 ZWJ 序列中间切开会让组合 emoji 在那一帧散成几个独立字符。
    static func stableLength(_ old: NSAttributedString, _ new: NSAttributedString) -> Int {
        let limit = min(old.length, new.length)
        guard limit > 0 else { return 0 }

        let oldText = old.string as NSString
        let newText = new.string as NSString

        // 1. 公共字符前缀，按 UTF-16 单元逐个比，发散即停（不扫全长）。
        var common = 0
        while common < limit, oldText.character(at: common) == newText.character(at: common) {
            common += 1
        }
        guard common > 0 else { return 0 }

        // 2. 属性比对：同时推进两边的 run，第一次发散就截断到该 run 的起点。
        var stable = 0
        var cursor = 0
        while cursor < common {
            var oldRange = NSRange(location: 0, length: 0)
            var newRange = NSRange(location: 0, length: 0)
            let oldAttributes = old.attributes(at: cursor, effectiveRange: &oldRange)
            let newAttributes = new.attributes(at: cursor, effectiveRange: &newRange)
            guard attributesEqual(oldAttributes, newAttributes) else { break }
            // 两边 run 与公共字符前缀三者的共同终点
            let end = min(oldRange.upperBound, newRange.upperBound, common)
            guard end > cursor else { break }   // effectiveRange 长度恒 ≥ 1，这里只是防御
            stable = end
            cursor = end
        }
        guard stable > 0 else { return 0 }

        return characterBoundary(in: oldText, notAfter: stable)
    }

    // MARK: - 私有

    /// 属性字典比较。
    ///
    /// 值类型五花八门（`UIFont`/`UIColor`/`NSParagraphStyle`/`NSNumber`/`URL`/`String`），
    /// 统一桥接成 `NSObject` 用 `isEqual` 比。桥接失败时返回 `false`——那只会导致
    /// 多替换一些字符（慢一点），不会产生错误结果，是安全的那个方向。
    private static func attributesEqual(_ lhs: [NSAttributedString.Key: Any],
                                        _ rhs: [NSAttributedString.Key: Any]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (key, lhsValue) in lhs {
            guard let rhsValue = rhs[key],
                  let lhsObject = lhsValue as? NSObject,
                  let rhsObject = rhsValue as? NSObject,
                  lhsObject.isEqual(rhsObject) else { return false }
        }
        return true
    }

    /// 把偏移向下吸附到字位簇边界。落在簇内部时取该簇的起点。
    private static func characterBoundary(in text: NSString, notAfter index: Int) -> Int {
        // index == text.length 是合法边界（字符串末尾），且不能传给
        // rangeOfComposedCharacterSequence(at:)——那会越界。
        guard index > 0, index < text.length else { return index }
        let sequence = text.rangeOfComposedCharacterSequence(at: index)
        return sequence.location >= index ? index : sequence.location
    }
}
