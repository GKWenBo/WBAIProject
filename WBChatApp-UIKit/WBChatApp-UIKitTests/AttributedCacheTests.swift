import Foundation
import UIKit
import Testing
@testable import WBChatApp_UIKit

@Suite("渲染缓存")
struct AttributedCacheTests {

    private func sealed(_ text: String, ordinal: Int = 0) -> MarkdownBlock {
        MarkdownBlock(ordinal: ordinal, kind: .paragraph, rawText: text, isSealed: true)
    }

    private func open(_ text: String) -> MarkdownBlock {
        MarkdownBlock(ordinal: 0, kind: .paragraph, rawText: text, isSealed: false)
    }

    @Test("已闭合块只渲染一次")
    func sealedBlockRendersOnce() {
        let cache = AttributedCache()
        var renderCount = 0
        let block = sealed("内容")
        for _ in 0..<5 {
            _ = cache.attributedString(for: block) { b in
                renderCount += 1
                return NSAttributedString(string: b.rawText)
            }
        }
        #expect(renderCount == 1)
    }

    @Test("未闭合块每次都重新渲染")
    func openBlockAlwaysRenders() {
        let cache = AttributedCache()
        var renderCount = 0
        for _ in 0..<3 {
            _ = cache.attributedString(for: open("写到一半")) { b in
                renderCount += 1
                return NSAttributedString(string: b.rawText)
            }
        }
        #expect(renderCount == 3)
    }

    @Test("内容相同但 ordinal 不同的块共享缓存")
    func cacheIsContentAddressed() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("同样的话", ordinal: 0), render: render)
        _ = cache.attributedString(for: sealed("同样的话", ordinal: 7), render: render)
        #expect(renderCount == 1)
    }

    @Test("内容不同则各自渲染")
    func differentContentRendersSeparately() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("甲"), render: render)
        _ = cache.attributedString(for: sealed("乙"), render: render)
        #expect(renderCount == 2)
    }

    @Test("同宽度的高度只测量一次")
    func heightMeasuredOncePerWidth() {
        let cache = AttributedCache()
        var measureCount = 0
        let block = sealed("内容")
        let render: (MarkdownBlock) -> NSAttributedString = { NSAttributedString(string: $0.rawText) }
        for _ in 0..<4 {
            _ = cache.height(for: block, width: 320, render: render) { _ in
                measureCount += 1
                return 44
            }
        }
        #expect(measureCount == 1)
    }

    @Test("宽度变化触发重新测量")
    func widthChangeInvalidatesHeight() {
        let cache = AttributedCache()
        var measureCount = 0
        let block = sealed("内容")
        let render: (MarkdownBlock) -> NSAttributedString = { NSAttributedString(string: $0.rawText) }
        let measure: (NSAttributedString) -> CGFloat = { _ in
            measureCount += 1
            return 44
        }
        _ = cache.height(for: block, width: 320, render: render, measure: measure)
        _ = cache.height(for: block, width: 375, render: render, measure: measure)
        #expect(measureCount == 2)
    }

    @Test("宽度存在浮点误差时仍命中同一缓存条目")
    func widthWithFloatingPointNoiseHitsSameEntry() {
        let cache = AttributedCache()
        var measureCount = 0
        let block = sealed("内容")
        let render: (MarkdownBlock) -> NSAttributedString = { NSAttributedString(string: $0.rawText) }
        let measure: (NSAttributedString) -> CGFloat = { _ in
            measureCount += 1
            return 44
        }
        // 用 nextUp 而非 .ulpOfOne：320.0 的 ulp（约 5.68e-14）远大于 .ulpOfOne
        // （1.0 的 ulp，约 2.22e-16），后者加上去会被舍入吞掉，根本测不出扰动。
        _ = cache.height(for: block, width: 320.0, render: render, measure: measure)
        _ = cache.height(for: block, width: 320.0.nextUp, render: render, measure: measure)
        #expect(measureCount == 1)
    }

    @Test("未闭合块的高度每次重测")
    func openBlockHeightNotCached() {
        let cache = AttributedCache()
        var measureCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { NSAttributedString(string: $0.rawText) }
        for _ in 0..<3 {
            _ = cache.height(for: open("变化中"), width: 320, render: render) { _ in
                measureCount += 1
                return 44
            }
        }
        #expect(measureCount == 3)
    }

    @Test("removeAll 清空后重新渲染")
    func removeAllClearsCache() {
        let cache = AttributedCache()
        var renderCount = 0
        let render: (MarkdownBlock) -> NSAttributedString = { b in
            renderCount += 1
            return NSAttributedString(string: b.rawText)
        }
        _ = cache.attributedString(for: sealed("内容"), render: render)
        cache.removeAll()
        _ = cache.attributedString(for: sealed("内容"), render: render)
        #expect(renderCount == 2)
    }

    @Test("返回的属性串内容正确")
    func returnsCorrectValue() {
        let cache = AttributedCache()
        let result = cache.attributedString(for: sealed("你好")) {
            NSAttributedString(string: $0.rawText)
        }
        #expect(result.string == "你好")
    }
}
