import UIKit

/// 块级渲染缓存。
///
/// **只缓存已闭合的块**：未闭合的块每帧都在变，缓存它没有意义还会撑爆内存。
/// 这正是「已闭合块只解析一次」这条性能承诺的兑现处。
///
/// **线程安全约定**：本类型假定所有调用都发生在主线程，内部不做同步。
/// `Entry.heights` 是普通字典，`height(for:width:render:measure:)` 内部对它做
/// 读后写；两个线程同时对同一已闭合块调用 `height` 会产生数据竞争甚至崩溃。
/// 调用方（视图层）本来就都在主线程，因此这里不加锁，避免不必要的开销。
final class AttributedCache {

    /// 一个已闭合块的渲染结果，以及它在各宽度下测得的高度
    private final class Entry {
        let attributedString: NSAttributedString
        /// 宽度 → 高度
        var heights: [CGFloat: CGFloat] = [:]
        init(attributedString: NSAttributedString) {
            self.attributedString = attributedString
        }
    }

    /// 以 `MarkdownBlock.cacheKey` 为键，内存紧张时系统自动淘汰
    private let storage = NSCache<NSNumber, Entry>()

    init(countLimit: Int = 400) {
        storage.countLimit = countLimit
    }

    /// - Parameter render: 必须是对同一 block 产出等价属性串的纯函数。本方法与
    ///   `height(for:width:render:measure:)` 各自独立判断缓存条目是否存在、各自可能用
    ///   自己收到的闭包建立条目；若两处传入的 `render` 逻辑不等价，会出现「用 A 闭包建的
    ///   条目被当作 B 闭包的结果复用」的静默错配。
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
    ///
    /// - Parameters:
    ///   - render: 必须是对同一 block 产出等价属性串的纯函数，约定同
    ///     `attributedString(for:render:)`。
    ///   - width: 内部会按屏幕像素量化后再作为缓存键，见 `quantized(width:)`。
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
        let quantizedWidth = Self.quantized(width: width)
        if let cached = entry.heights[quantizedWidth] { return cached }
        let measured = measure(entry.attributedString)
        entry.heights[quantizedWidth] = measured
        return measured
    }

    /// 屏幕像素量化粒度：3 覆盖了 @3x 设备（也细分了 @1x / @2x），
    /// 用固定粒度而不是 `UIScreen.main.scale`——后者在 iOS 17+ 被标记 deprecated，
    /// 且把缓存的行为绑死在运行环境上，不利于测试与推理。
    private static let widthQuantizationScale: CGFloat = 3

    /// 把宽度量化到屏幕像素粒度再返回。
    ///
    /// 调用方传入的 width 来自 safe area、Auto Layout 约束求解等浮点运算路径，
    /// 两次算出的值可能只差一个 ulp。若直接拿浮点数做字典键，这种误差会让
    /// `heights` 缓存静默失效——不会报错，只会表现为高度反复重新测量、性能变差。
    /// 因此先按屏幕像素粒度取整，再用作缓存键。
    private static func quantized(width: CGFloat) -> CGFloat {
        (width * widthQuantizationScale).rounded() / widthQuantizationScale
    }

    func removeAll() {
        storage.removeAllObjects()
    }
}
