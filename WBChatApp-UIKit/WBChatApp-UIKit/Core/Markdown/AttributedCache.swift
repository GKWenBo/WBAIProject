import UIKit

/// 块级渲染缓存。
///
/// **只缓存已闭合的块**：未闭合的块每帧都在变，缓存它没有意义还会撑爆内存。
/// 这正是「已闭合块只解析一次」这条性能承诺的兑现处。
final class AttributedCache {

    private final class Entry {
        let attributedString: NSAttributedString
        /// 宽度 → 高度
        var heights: [CGFloat: CGFloat] = [:]
        init(attributedString: NSAttributedString) {
            self.attributedString = attributedString
        }
    }

    private let storage = NSCache<NSNumber, Entry>()

    init(countLimit: Int = 400) {
        storage.countLimit = countLimit
    }

    func attributedString(for block: MarkdownBlock,
                          render: (MarkdownBlock) -> NSAttributedString) -> NSAttributedString {
        guard block.isSealed else { return render(block) }

        let key = NSNumber(value: block.cacheKey)
        if let entry = storage.object(forKey: key) {
            return entry.attributedString
        }
        let rendered = render(block)
        storage.setObject(Entry(attributedString: rendered), forKey: key)
        return rendered
    }

    /// 计算块在给定宽度下的高度。
    ///
    /// 接受 `render` 闭包是因为高度依赖属性串，而调用方不能保证 `height` 之前一定
    /// 调过 `attributedString(for:render:)`——若缓存条目缺失，这里会用 `render` 现建一个，
    /// 而不是用空字符串糊弄测量（那样测出来的高度恒为空串高度，是错的）。
    func height(for block: MarkdownBlock,
                width: CGFloat,
                render: (MarkdownBlock) -> NSAttributedString,
                measure: (NSAttributedString) -> CGFloat) -> CGFloat {
        guard block.isSealed else {
            return measure(render(block))
        }

        let key = NSNumber(value: block.cacheKey)
        let entry: Entry
        if let existing = storage.object(forKey: key) {
            entry = existing
        } else {
            entry = Entry(attributedString: render(block))
            storage.setObject(entry, forKey: key)
        }
        if let cached = entry.heights[width] { return cached }
        let measured = measure(entry.attributedString)
        entry.heights[width] = measured
        return measured
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
