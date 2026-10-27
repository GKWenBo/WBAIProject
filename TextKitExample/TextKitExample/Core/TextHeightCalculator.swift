//
//  TextHeightCalculator.swift
//  TextKitExample
//
//  案例 1：文本高度预计算 / 后台排版
//

import UIKit

/// 不需要视图实例的文本测高器，可在后台线程使用，自带高度缓存。
///
/// 列表（IM、Feed、AI 对话）里最常见的用法：滑动时主线程只负责展示，高度提前在后台算好。
///
/// ## 为什么不用 `boundingRect(with:options:context:)`
///
/// `boundingRect` 和 TextKit 的结果能差 0~3pt，而且误差随字号、行数变化，不是一个固定偏移，
/// 没法靠经验公式补。`UITextView` 本身就由 TextKit 驱动，**用同一个引擎量，一致性是结构性的**，
/// 换字号、换系统版本都不会突然失准。
///
/// 这里用 TextKit 2（`NSTextContentStorage` + `NSTextLayoutManager` + `NSTextContainer`），
/// 因为 iOS 15 之后 `UITextView` 默认就是 TextKit 2，量的和显示的是同一套实现。
///
/// ## 线程约定
///
/// TextKit 的对象不是线程安全的，但"一套栈只在一条线程上用、且不挂到任何视图上"就是安全的。
/// 这里把这条约定写进代码：所有 TextKit 对象只在私有串行队列上访问，外部怎么调都不会破坏它。
/// 工程开了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，所以这个类显式声明 `nonisolated`，
/// 否则它会被默认绑到主线程上，后台测高就无从谈起。
///
/// ## 前提
///
/// 容器配置走 `TextStyle.configure(_:width:)`，展示用的 `UITextView` 走
/// `TextStyle.configure(_:)`。两边必须用同一套约定，否则算出来的高度和实际排版不一致。
///
/// 所有可变状态都只在私有串行队列上访问，所以可以安全地标记为 `@unchecked Sendable`。
nonisolated final class TextHeightCalculator: @unchecked Sendable {

    // 直接用属性串本身做 key，不用 hashValue —— 哈希碰撞在这里的后果是"某条消息高度错了"，
    // 排查成本远高于多存一个引用的内存开销。
    private struct CacheKey: Hashable {
        let text: NSAttributedString
        let width: CGFloat
    }

    private let queue = DispatchQueue(label: "TextKitExample.TextHeightCalculator", qos: .userInitiated)

    private let contentStorage = NSTextContentStorage()
    private let layoutManager = NSTextLayoutManager()
    private let container = NSTextContainer()

    private var cache: [CacheKey: CGFloat] = [:]
    private let cacheLimit: Int
    private var measureCount = 0

    /// 实际排版过的次数，供测试断言缓存确实命中。
    var measureCountForTesting: Int { queue.sync { measureCount } }

    /// 当前缓存条数。
    var cachedCount: Int { queue.sync { cache.count } }

    init(cacheLimit: Int = 500) {
        self.cacheLimit = cacheLimit
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
    }

    // MARK: - 测高

    /// 同步测高。内部会切到私有队列，调用方在哪条线程上调都可以。
    ///
    /// - Parameter width: `nil` 表示不限宽、不换行（代码块靠横向滚动查看时用）。
    func height(of text: NSAttributedString, width: CGFloat?) -> CGFloat {
        guard text.length > 0 else { return 0 }
        // 传进来的可能是 NSMutableAttributedString，拷一份保证跨线程读取时内容不会被改。
        let snapshot = text.copy() as! NSAttributedString
        return queue.sync { measure(snapshot, width: width) }
    }

    /// 异步测高，结果回主线程。列表预热高度时用这个。
    func height(of text: NSAttributedString,
                width: CGFloat?,
                completion: @escaping @MainActor (CGFloat) -> Void) {
        guard text.length > 0 else {
            Task { @MainActor in completion(0) }
            return
        }
        // copy() 得到的是不可变副本，之后只在私有队列上读取，跨线程传递是安全的。
        nonisolated(unsafe) let snapshot = text.copy() as! NSAttributedString
        queue.async {
            let height = self.measure(snapshot, width: width)
            Task { @MainActor in completion(height) }
        }
    }

    /// 清空缓存。字号、主题、布局宽度变化后调用。
    func invalidateCache() {
        queue.sync { cache.removeAll(keepingCapacity: true) }
    }

    // MARK: - 私有队列上的实现

    private func measure(_ text: NSAttributedString, width: CGFloat?) -> CGFloat {
        let key = CacheKey(text: text, width: width ?? .infinity)
        if let cached = cache[key] { return cached }

        measureCount += 1
        TextStyle.configure(container, width: width)
        contentStorage.performEditingTransaction {
            contentStorage.textStorage?.setAttributedString(text)
        }
        layoutManager.ensureLayout(for: contentStorage.documentRange)
        // 向上取整：差半个像素就可能把最后一行的下半截切掉。
        let height = ceil(layoutManager.usageBoundsForTextContainer.height)

        // 到上限就整体清空。真实项目可以换成 LRU，这里保持最小实现。
        if cache.count >= cacheLimit {
            cache.removeAll(keepingCapacity: true)
        }
        cache[key] = height
        return height
    }
}
