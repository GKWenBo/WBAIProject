//
//  HighlightTextStorage.swift
//  TextKitExample
//
//  案例 6：语法高亮 / 实时富文本编辑器
//

import UIKit

/// 带增量语法高亮的 `NSTextStorage`。
///
/// 这是代码编辑器、Markdown 实时高亮的标准做法：继承 `NSTextStorage`，
/// 在 `processEditing()` 里只给刚编辑过的那几行重新上色。
/// 增量不是优化出来的，而是这个钩子天然带来的 —— `editedRange` 就是本次改动的范围。
///
/// ## 子类必须实现的四个方法
///
/// `NSTextStorage` 是个半抽象类，它只管变更通知，内容得自己存。四个 primitive：
/// `string`、`attributes(at:effectiveRange:)`、`replaceCharacters(in:with:)`、
/// `setAttributes(_:range:)`。后两个改完必须调 `edited(...)` 告诉排版层改了哪里，
/// 漏掉就会出现"文字变了但显示没刷新"。
final class HighlightTextStorage: NSTextStorage {

    /// 一条高亮规则：匹配什么、染成什么颜色。
    struct Rule {
        let pattern: String
        let color: UIColor

        var regex: NSRegularExpression? {
            try? NSRegularExpression(pattern: pattern)
        }
    }

    /// 没有命中任何规则时的基础属性。
    var defaultAttributes: [NSAttributedString.Key: Any] = TextStyle.code

    /// 上一次实际重新着色的字符范围，供演示展示"只重算了这几行"。
    private(set) var lastHighlightedRange = NSRange(location: 0, length: 0)

    private let backing = NSMutableAttributedString()
    private let rules: [Rule]
    private let compiledRules: [(NSRegularExpression, UIColor)]

    init(rules: [Rule] = Rule.swift) {
        self.rules = rules
        self.compiledRules = rules.compactMap { rule in
            rule.regex.map { ($0, rule.color) }
        }
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) 未实现，本工程不使用 storyboard")
    }

    // MARK: - 四个必须实现的方法

    override var string: String { backing.string }

    override func attributes(at location: Int,
                             effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters,
               range: range,
               changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    // MARK: - 增量高亮

    /// 每次编辑结束前都会走这里，`editedRange` 就是本次改动的范围。
    override func processEditing() {
        // 把范围扩到整行：一个字符的改动也可能让整行的词法结构变化（比如刚输入了一个引号）。
        let lineRange = (string as NSString).lineRange(for: editedRange)
        highlight(lineRange)
        lastHighlightedRange = lineRange
        super.processEditing()
    }

    /// 给指定范围重新上色。先铺基础属性，再按规则覆盖。
    func highlight(_ range: NSRange) {
        guard range.length > 0, NSMaxRange(range) <= backing.length else { return }

        backing.setAttributes(defaultAttributes, range: range)
        for (regex, color) in compiledRules {
            regex.enumerateMatches(in: string, range: range) { match, _, _ in
                guard let match else { return }
                backing.addAttribute(.foregroundColor, value: color, range: match.range)
            }
        }
        // 这里直接改 backing 没有走 setAttributes(_:range:)，所以要手动通知一次。
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    /// 全量上色。设置初始文本后调用一次。
    func highlightAll() {
        highlight(NSRange(location: 0, length: backing.length))
    }
}

// MARK: - 一套够用的 Swift 规则

extension HighlightTextStorage.Rule {

    /// 顺序有讲究：后面的规则会覆盖前面的，所以注释和字符串放最后，
    /// 这样注释里的关键字不会被染成关键字色。
    static let swift: [HighlightTextStorage.Rule] = [
        .init(pattern: "\\b[0-9]+(\\.[0-9]+)?\\b", color: .systemPurple),
        .init(pattern: "\\b(func|let|var|return|override|class|final|struct|enum|if|guard|else|for|in|private|import|self)\\b",
              color: .systemPink),
        .init(pattern: "\"[^\"\\n]*\"", color: .systemOrange),
        .init(pattern: "//[^\\n]*", color: .systemGreen)
    ]
}
