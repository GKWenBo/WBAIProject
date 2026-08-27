import UIKit
import Markdown

extension NSAttributedString.Key {
    /// 链接目标。不用系统的 .link，是为了自己控制点击与配色。
    static let wbLinkURL = NSAttributedString.Key("wbLinkURL")
}

/// 把单个 Markdown 块渲染成属性串。
///
/// 刻意只处理**一个块**：swift-markdown 每次只解析几十到几百字，
/// 配合已闭合块的缓存，整条消息的渲染代价才是线性的。
final class AttributedRenderer {

    private let theme: MarkdownTheme
    private let highlighter: CodeHighlighter

    init(theme: MarkdownTheme = .default, highlighter: CodeHighlighter = CodeHighlighter()) {
        self.theme = theme
        self.highlighter = highlighter
    }

    func render(_ block: MarkdownBlock) -> NSAttributedString {
        // 代码块不经过 swift-markdown：既省一次解析，也便于未闭合时照样出图
        if case .codeFence(let language) = block.kind {
            return highlighter.highlight(code: codeText(of: block),
                                         language: language,
                                         theme: theme)
        }

        let document = Document(parsing: block.rawText)
        let result = NSMutableAttributedString()
        for child in document.children {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(renderBlockMarkup(child))
        }
        applyParagraphStyle(to: result, kind: block.kind)
        return result
    }

    /// 剥掉围栏行，拿到纯代码。未闭合的块没有结尾围栏，也要能正确处理。
    func codeText(of block: MarkdownBlock) -> String {
        var lines = block.rawText.components(separatedBy: "\n")
        if let first = lines.first,
           first.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            || first.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
            lines.removeFirst()
        }
        if let last = lines.last,
           last.trimmingCharacters(in: .whitespaces).hasPrefix("```")
            || last.trimmingCharacters(in: .whitespaces).hasPrefix("~~~") {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 块级

    private func renderBlockMarkup(_ markup: Markup) -> NSAttributedString {
        switch markup {
        case let heading as Heading:
            let result = NSMutableAttributedString(attributedString: renderInlines(heading))
            result.addAttributes([.font: theme.headingFont(level: heading.level)],
                                 range: NSRange(location: 0, length: result.length))
            return result

        case let paragraph as Paragraph:
            return renderInlines(paragraph)

        case let quote as BlockQuote:
            let result = NSMutableAttributedString()
            for child in quote.children {
                if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(renderBlockMarkup(child))
            }
            result.addAttributes([.foregroundColor: theme.secondaryColor],
                                 range: NSRange(location: 0, length: result.length))
            return result

        case let list as UnorderedList:
            return renderList(items: Array(list.listItems), marker: { _ in "• " })

        case let list as OrderedList:
            let start = Int(list.startIndex)
            return renderList(items: Array(list.listItems), marker: { "\(start + $0). " })

        case is ThematicBreak:
            // 分割线由独立的 DividerBlockView 画，这里不产出文本
            return NSAttributedString()

        case let table as Markdown.Table:
            return renderTable(table)

        case let code as CodeBlock:
            return highlighter.highlight(code: code.code.trimmingCharacters(in: .newlines),
                                         language: code.language,
                                         theme: theme)

        default:
            // 兜底：把纯文本取出来，绝不丢内容
            return NSAttributedString(string: markup.format(),
                                      attributes: [.font: theme.bodyFont,
                                                   .foregroundColor: theme.textColor])
        }
    }

    private func renderList(items: [ListItem], marker: (Int) -> String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, item) in items.enumerated() {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(string: marker(index),
                                             attributes: [.font: theme.bodyFont,
                                                          .foregroundColor: theme.secondaryColor]))
            // 一个列表项可能含多个子块（嵌套列表、多段落），子块之间要换行；
            // 但标记（"• "）和第一个子块之间不能插入换行，所以用子块下标判断，不能沿用 result.length。
            for (childIndex, child) in item.children.enumerated() {
                if childIndex > 0 { result.append(NSAttributedString(string: "\n")) }
                result.append(renderBlockMarkup(child))
            }
        }
        return result
    }

    private func renderTable(_ table: Markdown.Table) -> NSAttributedString {
        // 目前没有专门画表格格线的视图（不存在 TableBlockView）：表格实际是渲染成
        // 制表符拼接的纯文本，每行一个 NSAttributedString 行，靠 "\t" 分隔单元格，
        // 落到普通的 MarkdownTextBlockView 里显示，没有格线/对齐等表格排版。
        let result = NSMutableAttributedString()
        func appendRow(_ cells: [String]) {
            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(NSAttributedString(string: cells.joined(separator: "\t"),
                                             attributes: [.font: theme.bodyFont,
                                                          .foregroundColor: theme.textColor]))
        }
        appendRow(table.head.cells.map { $0.plainText })
        for row in table.body.rows {
            appendRow(row.cells.map { $0.plainText })
        }
        return result
    }

    // MARK: - 行内

    private func renderInlines(_ container: Markup) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in container.children {
            result.append(renderInline(child, base: baseAttributes))
        }
        return result
    }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: theme.bodyFont, .foregroundColor: theme.textColor]
    }

    private func renderInline(_ markup: Markup,
                              base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        switch markup {
        case let text as Markdown.Text:
            return NSAttributedString(string: text.string, attributes: base)

        case is SoftBreak:
            return NSAttributedString(string: " ", attributes: base)

        case is LineBreak:
            return NSAttributedString(string: "\n", attributes: base)

        case let code as InlineCode:
            var attributes = base
            attributes[.font] = theme.monoFont
            attributes[.backgroundColor] = Theme.codeBackground
            return NSAttributedString(string: code.code, attributes: attributes)

        case let strong as Strong:
            return renderChildren(strong, base: adding(.traitBold, to: base))

        case let emphasis as Emphasis:
            return renderChildren(emphasis, base: adding(.traitItalic, to: base))

        case let strike as Strikethrough:
            var attributes = base
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            return renderChildren(strike, base: attributes)

        case let link as Markdown.Link:
            var attributes = base
            attributes[.foregroundColor] = theme.linkColor
            if let destination = link.destination, let url = URL(string: destination) {
                attributes[.wbLinkURL] = url
            }
            return renderChildren(link, base: attributes)

        default:
            return renderChildren(markup, base: base)
        }
    }

    private func renderChildren(_ markup: Markup,
                                base: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in markup.children {
            result.append(renderInline(child, base: base))
        }
        return result
    }

    private func adding(_ trait: UIFontDescriptor.SymbolicTraits,
                        to attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = attributes
        let font = (attributes[.font] as? UIFont) ?? theme.bodyFont
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            result[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
        }
        return result
    }

    private func applyParagraphStyle(to attributed: NSMutableAttributedString,
                                     kind: MarkdownBlockKind) {
        guard attributed.length > 0 else { return }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        if case .list = kind {
            style.headIndent = theme.listIndent
        }
        attributed.addAttribute(.paragraphStyle, value: style,
                                range: NSRange(location: 0, length: attributed.length))
    }
}
