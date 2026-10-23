import UIKit
import Testing
@testable import WBChatApp_UIKit

/// TextKit 测量器与真实视图渲染尺寸的一致性。
///
/// 这是「测高不再需要活视图」这条改动的前提条件：对不齐就会出现行高与实际排版
/// 脱节，文字被裁或留白。`TextKitMeasurer.canMeasure(_:)` 是允许名单的唯一事实
/// 来源，名单内的块类型必须完全一致，回归就红；名单外的类型由调用方回退到视图
/// 测量，这里只记录偏差供参考。
@Suite("TextKit 测量一致性")
@MainActor
struct TextKitMeasurerParityTests {

    private let renderer = AttributedRenderer()
    private let measurer = TextKitMeasurer()

    /// 常见内容宽度，外加一个小数宽度用来打到宽度量化逻辑
    private static let widths: [CGFloat] = [343, 320, 414, 200, 287.5]

    private struct Sample {
        let name: String
        let kind: MarkdownBlockKind
        let raw: String
    }

    private static let samples: [Sample] = [
        Sample(name: "短中文段落", kind: .paragraph, raw: "简短的一句话。"),
        Sample(name: "长中文段落", kind: .paragraph,
               raw: String(repeating: "这是一段用来测试换行的中文内容，", count: 12)),
        Sample(name: "纯 ASCII 段落", kind: .paragraph,
               raw: String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 8)),
        Sample(name: "中英混排", kind: .paragraph,
               raw: String(repeating: "混排 mixed content 测试 42 次，", count: 10)),
        Sample(name: "含 emoji 与 ZWJ 序列", kind: .paragraph,
               raw: "进度 50%👍 已完成，下一步见👨‍💻 文档，再来一个👨‍👩‍👧‍👦 家庭。"),
        Sample(name: "超长不可断 URL", kind: .paragraph,
               raw: "参考 https://example.com/a/very/long/path/that/cannot/be/broken/easily/at/all/segment 这里"),
        Sample(name: "行内代码与强调", kind: .paragraph,
               raw: "调用 `applyIncrementally(_:)` 时要**注意**线程，*不要*跨线程。"),
        Sample(name: "链接段落", kind: .paragraph,
               raw: "详见[官方文档](https://developer.apple.com/documentation/uikit)说明。"),
        Sample(name: "一级标题", kind: .heading(level: 1), raw: "# 这是一级标题"),
        Sample(name: "三级标题", kind: .heading(level: 3), raw: "### 这是三级标题，稍微长一点点"),
        Sample(name: "无序列表", kind: .list(ordered: false),
               raw: "- 第一项内容\n- 第二项内容稍微长一些需要换行才放得下\n- 第三项"),
        Sample(name: "有序列表", kind: .list(ordered: true),
               raw: "1. 第一步\n2. 第二步要做的事情比较多所以这一行会换行\n3. 第三步"),
        Sample(name: "嵌套列表", kind: .list(ordered: false),
               raw: "- 父项\n  - 子项一\n  - 子项二"),
        Sample(name: "引用块", kind: .blockQuote,
               raw: "> 引用的内容也要正确换行，这里写得长一点以便触发多行排版。"),
        Sample(name: "表格", kind: .table,
               raw: "| 块类型 | 是否增量 |\n| --- | --- |\n| 已闭合块 | 只解析一次 |\n| 未闭合块 | 每帧重解析 |"),
        Sample(name: "演示脚本段落", kind: .paragraph,
               raw: "当前还没有配置 API Key，这段内容是**本地模拟**生成的，用来演示流式渲染。"),
        // 名单外的类型，只记录偏差
        Sample(name: "代码块", kind: .codeFence(language: "swift"),
               raw: "```swift\nfunc greet(_ name: String) -> String {\n    return \"你好，\\(name)\"\n}\n```"),
    ]

    /// 视图实际算出来的高度
    private func viewHeight(_ sample: Sample, width: CGFloat) -> CGFloat {
        let block = MarkdownBlock(ordinal: 0, kind: sample.kind, rawText: sample.raw, isSealed: true)
        let attributed = renderer.render(block)
        if case .codeFence = sample.kind {
            let view = CodeBlockView()
            view.configure(block: block, attributed: attributed, renderer: renderer)
            return view.heightThatFits(width: width)
        }
        let view = MarkdownTextBlockView()
        view.configure(block: block, attributed: attributed, renderer: renderer)
        return view.heightThatFits(width: width)
    }

    /// 测量器算出来的高度（含该块类型的装饰）
    private func measuredHeight(_ sample: Sample, width: CGFloat) -> CGFloat {
        let block = MarkdownBlock(ordinal: 0, kind: sample.kind, rawText: sample.raw, isSealed: true)
        let attributed = renderer.render(block)
        if case .codeFence = sample.kind {
            return measurer.height(of: attributed, width: nil) + BlockMetrics.codeChromeHeight
        }
        let available = BlockMetrics.textContentWidth(for: sample.kind, in: width)
        return measurer.height(of: attributed, width: available)
    }

    @Test("允许名单内的块类型与视图测量完全一致")
    func parityForMeasurableKinds() {
        for sample in Self.samples where TextKitMeasurer.canMeasure(sample.kind) {
            for width in Self.widths {
                let fromView = viewHeight(sample, width: width)
                let fromMeasurer = measuredHeight(sample, width: width)
                #expect(fromView == fromMeasurer,
                        "「\(sample.name)」在宽度 \(width) 下不一致：视图 \(fromView)，测量器 \(fromMeasurer)，差 \(fromMeasurer - fromView)")
            }
        }
    }

    @Test("名单外的块类型记录偏差，不做断言")
    func reportDeviationForExcludedKinds() {
        for sample in Self.samples where !TextKitMeasurer.canMeasure(sample.kind) {
            for width in Self.widths {
                let delta = measuredHeight(sample, width: width) - viewHeight(sample, width: width)
                if delta != 0 {
                    print("[parity] 名单外「\(sample.name)」宽度 \(width) 偏差 \(delta)")
                }
            }
        }
    }

    @Test("空属性串高度为 0")
    func emptyStringHasZeroHeight() {
        #expect(measurer.height(of: NSAttributedString(), width: 343) == 0)
    }

    @Test("同内容同宽度测量结果稳定")
    func measurementIsStable() {
        let block = MarkdownBlock(ordinal: 0, kind: .paragraph,
                                  rawText: "稳定的一段内容，需要换行才够长。", isSealed: true)
        let attributed = renderer.render(block)
        #expect(measurer.height(of: attributed, width: 200)
                == measurer.height(of: attributed, width: 200))
    }

    @Test("宽度变窄高度变高")
    func narrowerIsTaller() {
        let block = MarkdownBlock(ordinal: 0, kind: .paragraph,
                                  rawText: String(repeating: "文字内容", count: 40), isSealed: true)
        let attributed = renderer.render(block)
        #expect(measurer.height(of: attributed, width: 150)
                > measurer.height(of: attributed, width: 350))
    }
}
