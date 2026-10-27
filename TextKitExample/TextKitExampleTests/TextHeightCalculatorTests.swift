//
//  TextHeightCalculatorTests.swift
//  TextKitExampleTests
//

import Testing
import UIKit
@testable import TextKitExample

@MainActor
@Suite("测高器")
struct TextHeightCalculatorTests {

    /// 视图侧的对照测量：同一套容器约定下 `UITextView` 的实际排版高度。
    private func viewHeight(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        let textView = UITextView()
        TextStyle.configure(textView)
        textView.attributedText = text
        return ceil(textView.sizeThatFits(CGSize(width: width,
                                                 height: .greatestFiniteMagnitude)).height)
    }

    @Test("测量结果与 UITextView 实际排版一致")
    func matchesTextView() {
        let calculator = TextHeightCalculator()

        for fontSize in [12.0, 16.0, 22.0] as [CGFloat] {
            for lineSpacing in [0.0, 6.0, 12.0] as [CGFloat] {
                for width in [160.0, 280.0, 360.0] as [CGFloat] {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: fontSize),
                        .paragraphStyle: TextStyle.paragraphStyle(lineSpacing: lineSpacing)
                    ]
                    let text = NSAttributedString(string: SampleText.article, attributes: attributes)

                    #expect(calculator.height(of: text, width: width) == viewHeight(of: text, width: width),
                            "字号 \(fontSize) 行距 \(lineSpacing) 宽度 \(width) 不一致")
                }
            }
        }
    }

    @Test("同样的输入只排版一次")
    func cacheHits() {
        let calculator = TextHeightCalculator()
        let text = NSAttributedString(string: SampleText.article, attributes: TextStyle.body)

        let first = calculator.height(of: text, width: 300)
        #expect(calculator.measureCountForTesting == 1)

        for _ in 0..<5 {
            #expect(calculator.height(of: text, width: 300) == first)
        }
        #expect(calculator.measureCountForTesting == 1)

        // 宽度变了就是另一次测量。
        _ = calculator.height(of: text, width: 240)
        #expect(calculator.measureCountForTesting == 2)
    }

    @Test("清缓存后重新排版")
    func invalidate() {
        let calculator = TextHeightCalculator()
        let text = NSAttributedString(string: "一行字", attributes: TextStyle.body)

        _ = calculator.height(of: text, width: 300)
        calculator.invalidateCache()
        #expect(calculator.cachedCount == 0)

        _ = calculator.height(of: text, width: 300)
        #expect(calculator.measureCountForTesting == 2)
    }

    @Test("空文本高度为 0 且不触发排版")
    func emptyText() {
        let calculator = TextHeightCalculator()
        #expect(calculator.height(of: NSAttributedString(), width: 300) == 0)
        #expect(calculator.measureCountForTesting == 0)
    }

    @Test("可变属性串在测量期间被改也不影响结果")
    func snapshotsMutableInput() {
        let calculator = TextHeightCalculator()
        let mutable = NSMutableAttributedString(string: "第一行", attributes: TextStyle.body)

        let before = calculator.height(of: mutable, width: 300)
        mutable.append(NSAttributedString(string: "\n第二行\n第三行", attributes: TextStyle.body))
        let after = calculator.height(of: mutable, width: 300)

        #expect(after > before)
        #expect(calculator.measureCountForTesting == 2)
    }
}
