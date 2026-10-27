//
//  SampleText.swift
//  TextKitExample
//

import UIKit

/// 各案例共用的演示文本。
///
/// 刻意做成中英混排 + emoji + 长短不一：这三样最容易暴露排版和测高的误差。
enum SampleText {

    // MARK: - 案例 1：会话列表

    /// 长短差距很大的消息，用来看高度缓存的效果。
    static let messages: [String] = [
        "在吗？",
        "TextKit 的排版引擎分三层：NSTextStorage 存文本和属性，NSLayoutManager 负责把字符变成字形并排版，NSTextContainer 描述可排版的区域形状。",
        "好 👌",
        "列表里最常见的用法是把高度算在后台：主线程只负责展示，滑动就不会掉帧。注意 TextKit 对象不能跨线程共享，一套栈只在一个线程里用。",
        "boundingRect(with:) 和 TextKit 的结果差 0~3pt，而且误差随字号和行数变化，不是一个固定偏移 —— 所以没法靠经验公式补。",
        "明白了，我试试 🚀",
        "还有一点容易漏：UITextView 默认 textContainerInset 是上下 8，lineFragmentPadding 是 5。测量栈要是没对齐这两个值，算出来的高度就偏。",
        "收到",
        "AI 对话流式输出时，已经闭合的块可以缓存高度，只有最后一个块需要反复重排。这样长会话滚动才稳。",
        "👍🏻"
    ]

    // MARK: - 案例 2：社交文本

    /// 带 @、话题、链接三类可点击标记的富文本。
    static func social() -> NSAttributedString {
        let text = """
        @文波 在 #TextKit# 里提到：UILabel 本身不提供字符级点击，常规做法是自己养一套参数一致的 \
        TextKit 栈做坐标换算。细节可以看 https://developer.apple.com/documentation/uikit/textkit ，\
        也欢迎在 #iOS面试# 里一起讨论。
        """

        let attributed = NSMutableAttributedString(string: text, attributes: TextStyle.body)
        attributed.markFirst("@文波", kind: .mention, payload: "wenbo")
        attributed.markFirst("#TextKit#", kind: .hashtag, payload: "TextKit")
        attributed.markFirst("#iOS面试#", kind: .hashtag, payload: "iOS面试")
        attributed.markFirst("https://developer.apple.com/documentation/uikit/textkit",
                             kind: .link,
                             payload: "https://developer.apple.com/documentation/uikit/textkit")
        return attributed
    }

    // MARK: - 案例 3：Markdown 风格装饰

    /// 混合代码块底色、引用竖线、行内圆角高亮的文本。
    static func decorated() -> NSAttributedString {
        let attributed = NSMutableAttributedString()

        attributed.append(NSAttributedString(string: "TextKit 的背景装饰\n\n", attributes: {
            var attrs = TextStyle.body
            attrs[.font] = UIFont.systemFont(ofSize: 20, weight: .semibold)
            return attrs
        }()))

        attributed.append(NSAttributedString(
            string: "NSAttributedString 的 .backgroundColor 只能画紧贴字形的方块，想画整行拉满的代码块底色、引用块左侧竖线、带圆角的标签背景，都得自己画。\n\n",
            attributes: TextStyle.body))

        let quote = NSMutableAttributedString(
            string: "继承 NSLayoutManager，重写 drawBackground(forGlyphRange:at:)，按自定义属性找到对应的行矩形自己画。\n\n",
            attributes: TextStyle.quote)
        quote.addAttribute(.textDecoration,
                           value: TextDecoration.blockQuoteBar,
                           range: NSRange(location: 0, length: quote.length))
        attributed.append(quote)

        let code = NSMutableAttributedString(
            string: "override func drawBackground(\n    forGlyphRange glyphsToShow: NSRange,\n    at origin: CGPoint\n) {\n    super.drawBackground(forGlyphRange: glyphsToShow, at: origin)\n}\n\n",
            attributes: TextStyle.code)
        code.addAttribute(.textDecoration,
                          value: TextDecoration.codeBlock,
                          range: NSRange(location: 0, length: code.length))
        attributed.append(code)

        let tail = NSMutableAttributedString(
            string: "行内的 enumerateEnclosingRects 能拿到一段字符覆盖的所有矩形，跨行也能正确分成几段。",
            attributes: TextStyle.body)
        if let range = tail.string.range(of: "enumerateEnclosingRects") {
            tail.addAttribute(.textDecoration,
                              value: TextDecoration.inlineHighlight,
                              range: NSRange(range, in: tail.string))
        }
        attributed.append(tail)

        return attributed
    }

    // MARK: - 案例 4 / 5 / 7 / 8：长文

    static let article = """
    TextKit 是 UIKit 文本显示的底层框架。UILabel、UITextView、UITextField 都建立在它之上，\
    所以一旦需求超出这几个控件的能力边界，往下一层直接用 TextKit 往往比自绘或换框架更省事。

    它的分工很清晰。NSTextStorage 是带属性的文本仓库，同时也是变更通知的发起方。\
    NSLayoutManager 把字符映射成字形，再按容器形状切成一行行 line fragment，是真正干排版的那一层。\
    NSTextContainer 只描述"可以排版的区域长什么样"，它甚至不必是矩形。

    理解这个分工之后，很多需求就有了直接的入手点。要让文字绕开一张图，就往容器上加 exclusionPaths；\
    要做阅读器分页，就让一个 layoutManager 挂多个容器，文字排满一个会自动流到下一个；\
    要做实时语法高亮，就继承 NSTextStorage，在 processEditing 里只给刚编辑过的那几行重新上色。

    iOS 15 之后还有 TextKit 2。它用 NSTextLayoutManager 替代 NSLayoutManager，\
    以视口为单位按需排版，长文表现更好，也更适合非矩形布局。但它只支持单个容器，\
    而且像 truncatedGlyphRange 这类精细查询还没有等价物，所以两套会长期共存。\
    真实项目里按需求挑，不必非得统一到一套。
    """

    static func articleAttributed(alignment: NSTextAlignment = .natural) -> NSAttributedString {
        var attrs = TextStyle.body
        attrs[.paragraphStyle] = TextStyle.paragraphStyle(alignment: alignment)
        return NSAttributedString(string: article, attributes: attrs)
    }

    // MARK: - 案例 6：代码片段

    static let swiftSnippet = """
    // 继承 NSTextStorage 做增量高亮
    final class HighlightTextStorage: NSTextStorage {

        private let backing = NSMutableAttributedString()
        private let keywords = ["func", "let", "var", "return"]

        override var string: String {
            return backing.string
        }

        override func processEditing() {
            let lines = (string as NSString).lineRange(for: editedRange)
            highlight(lines)   // 只重算编辑过的那几行
            super.processEditing()
        }
    }
    """
}

// MARK: - 打标记的小工具

private extension NSMutableAttributedString {

    /// 给第一次出现的 `substring` 打上点击标记并染成链接色。
    func markFirst(_ substring: String,
                   kind: TextTapToken.Kind,
                   payload: String,
                   color: UIColor = .systemBlue) {
        guard let range = string.range(of: substring) else { return }
        addAttributes([.tapToken: TextTapToken(kind: kind, payload: payload),
                       .foregroundColor: color],
                      range: NSRange(range, in: string))
    }
}
