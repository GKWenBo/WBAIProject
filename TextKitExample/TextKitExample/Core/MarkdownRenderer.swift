//
//  MarkdownRenderer.swift
//  TextKitExample
//
//  案例 11：Markdown 流式渲染 —— 一小段 Markdown 原文 → 富文本
//

import UIKit

/// 一个够演示用的迷你 Markdown 渲染器：标题、无序/有序列表、围栏代码块、`**粗体**`、`` `行内代码` ``。
///
/// 它是**纯函数**：同样的原文永远渲染出同样的富文本，而且每一行只由这一行自己
/// （加上围栏状态）决定。这是增量渲染成立的前提 —— 已闭合的块渲染一次后就能冻结，
/// 尾块每次从块起点整体重渲染，两者拼起来与"一次性渲染全文"逐字符一致。
///
/// 输出与原文**不等长**（`#`、围栏行、`**` 都被吃掉了），所以调用方不能拿原文偏移当 storage 偏移，
/// 必须另外记录渲染结果的长度，见 `MarkdownStreamSession`。
///
/// 局限：每个原文行对应一个段落，不处理"同一段落内软换行"；只支持一层列表；没有斜体、链接。
enum MarkdownRenderer {

    /// 渲染一段原文。`source` 必须从块的起点开始，围栏不能被从中间切开。
    static func render(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        var lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        // 以 "\n" 结尾时最后一项是空串，不是一行；否则最后一行没有换行，说明它还没写完。
        let lastLineIsComplete = source.hasSuffix("\n")
        if lastLineIsComplete { lines.removeLast() }

        var openFence: MarkdownBlockSplitter.Fence?

        for (index, line) in lines.enumerated() {
            let isIncomplete = !lastLineIsComplete && index == lines.count - 1
            let terminator = isIncomplete ? "" : "\n"

            // 1. 围栏状态机：围栏行本身不输出，中间的行按代码渲染（含空行）。
            if let fence = openFence {
                if MarkdownBlockSplitter.isClosingFence(line, matching: fence) {
                    openFence = nil
                } else {
                    result.append(codeLine(line, terminator: terminator))
                }
                continue
            }
            if let fence = MarkdownBlockSplitter.fence(of: line) {
                openFence = fence
                continue
            }

            // 2. 围栏之外的空行只是块分隔，不输出；间距由段落样式的 paragraphSpacing 负责。
            if line.allSatisfy(\.isWhitespace) { continue }

            // 3. 其余按块级前缀分类，再渲染行内样式。
            result.append(blockLine(line, terminator: terminator, isIncomplete: isIncomplete))
        }
        return result
    }

    // MARK: - 块级

    private static func codeLine(_ line: Substring, terminator: String) -> NSAttributedString {
        var attributes = TextStyle.code
        attributes[.backgroundColor] = UIColor.systemGray5
        attributes[.paragraphStyle] = paragraphStyle(spacing: 0)
        return NSAttributedString(string: String(line) + terminator, attributes: attributes)
    }

    private static func blockLine(_ line: Substring, terminator: String, isIncomplete: Bool) -> NSAttributedString {
        var text = line
        var attributes = TextStyle.body
        var prefix = ""
        var style = paragraphStyle(spacing: 8)

        if let heading = headingLevel(of: text) {
            // 标题：去掉 `#` 和空格，整行加粗放大。
            text = text.dropFirst(heading + 1)
            let size: CGFloat = [22, 19, 17][heading - 1]
            attributes[.font] = UIFont.boldSystemFont(ofSize: size)
        } else if let marker = listMarker(of: text) {
            // 列表：无序统一成 "• "，有序保留原编号；悬挂缩进让换行后的文字对齐到正文。
            text = text.dropFirst(marker.length)
            prefix = marker.bullet
            style = paragraphStyle(spacing: 4, headIndent: 18)
        }
        attributes[.paragraphStyle] = style

        // 行内样式要在去掉前缀之后做；末尾孤零零的 `*` 只在行未写完时才可能是半个 `**`，需要藏起来。
        let result = NSMutableAttributedString(string: prefix, attributes: attributes)
        result.append(inline(text, base: attributes, holdBackTrailingStar: isIncomplete))
        result.append(NSAttributedString(string: terminator, attributes: attributes))
        return result
    }

    private static func paragraphStyle(spacing: CGFloat, headIndent: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.setParagraphStyle(TextStyle.paragraphStyle())
        style.paragraphSpacing = spacing
        style.headIndent = headIndent
        return style
    }

    private static func headingLevel(of line: Substring) -> Int? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(level), line.dropFirst(level).first == " " else { return nil }
        return level
    }

    /// `length` 是原文里标记占的字符数，`bullet` 是渲染后显示的前缀。
    private static func listMarker(of line: Substring) -> (length: Int, bullet: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            return (2, "• ")
        }
        let digits = line.prefix(while: \.isNumber)
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            let length = digits.count + 2
            return (length, String(line.prefix(length)))
        }
        return nil
    }

    // MARK: - 行内

    /// 解析 `**粗体**` 和 `` `代码` ``。
    ///
    /// 用"开关"实现：遇到标记就翻转状态，之后的字符按当前状态着色。
    /// 好处是**未闭合的标记自然就生效到行尾**（`**加粗` 流到一半就已经是粗体），
    /// 相当于解析前自动补全了闭合符，不会出现"先显示原样 `**`，闭合后又跳变"的闪烁。
    private static func inline(_ text: Substring,
                               base: [NSAttributedString.Key: Any],
                               holdBackTrailingStar: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let characters = Array(text)
        var buffer = ""
        var isBold = false
        var isCode = false

        // 按当前状态把缓冲区写出去。必须在翻转状态之前调用。
        func flush() {
            guard !buffer.isEmpty else { return }
            var attributes = base
            if isBold, let font = base[.font] as? UIFont { attributes[.font] = font.bold() }
            if isCode {
                attributes[.font] = TextStyle.codeFont
                attributes[.backgroundColor] = UIColor.systemGray5
            }
            result.append(NSAttributedString(string: buffer, attributes: attributes))
            buffer = ""
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "`" {
                flush()
                isCode.toggle()
                index += 1
            } else if character == "*", !isCode {
                // 代码里的 `*` 只是普通字符；代码之外，`**` 才是粗体标记。
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    flush()
                    isBold.toggle()
                    index += 2
                } else if index + 1 == characters.count, holdBackTrailingStar {
                    // 行尾单个 `*`，下一块可能补成 `**`：先不显示，避免闪一下再消失。
                    index += 1
                } else {
                    buffer.append(character)
                    index += 1
                }
            } else {
                buffer.append(character)
                index += 1
            }
        }
        flush()
        return result
    }
}

private extension UIFont {
    /// 同字号的粗体版本；取不到粗体描述符时原样返回。
    func bold() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
