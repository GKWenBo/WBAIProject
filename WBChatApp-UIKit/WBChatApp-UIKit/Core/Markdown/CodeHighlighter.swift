import UIKit

enum CodeTokenKind: String {
    case keyword, string, comment, number, plain
}

extension NSAttributedString.Key {
    /// 标记 token 类型。渲染不用它，测试用它断言分词是否正确。
    static let wbCodeTokenKind = NSAttributedString.Key("wbCodeTokenKind")
}

/// 轻量语法高亮。
///
/// 用一遍线性扫描而非正则：注释与字符串会「吞掉」内部内容，
/// 从而天然避免「字符串里的 func 被标成关键字」这类误判。
struct CodeHighlighter: Sendable {

    private static let keywordsByLanguage: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "struct", "class",
                  "enum", "protocol", "extension", "import", "for", "in", "while", "switch",
                  "case", "default", "self", "init", "throws", "try", "async", "await",
                  "private", "public", "internal", "static", "some", "any", "nil", "true", "false"],
        "objc":  ["@interface", "@implementation", "@property", "@end", "void", "id", "self",
                  "if", "else", "return", "for", "while", "switch", "case", "nil", "YES", "NO",
                  "NSString", "NSInteger", "BOOL", "instancetype"],
        "javascript": ["function", "const", "let", "var", "if", "else", "return", "class",
                       "import", "export", "for", "while", "switch", "case", "async", "await",
                       "new", "this", "null", "undefined", "true", "false"],
        "python": ["def", "class", "if", "elif", "else", "return", "import", "from", "for",
                   "while", "try", "except", "finally", "with", "as", "lambda", "None",
                   "True", "False", "self", "async", "await"],
        "bash":  ["if", "then", "else", "fi", "for", "in", "do", "done", "while", "case",
                  "esac", "function", "echo", "export", "local", "return"],
    ]

    /// 语言别名归一
    private static let aliases: [String: String] = [
        "js": "javascript", "ts": "javascript", "typescript": "javascript",
        "py": "python", "sh": "bash", "shell": "bash", "zsh": "bash",
        "objective-c": "objc", "objectivec": "objc", "m": "objc",
    ]

    func highlight(code: String, language: String?, theme: MarkdownTheme) -> NSAttributedString {
        let normalized = language.map { $0.lowercased() }.map { Self.aliases[$0] ?? $0 }
        let keywords = normalized.flatMap { Self.keywordsByLanguage[$0] } ?? []

        let result = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: theme.monoFont,
                .foregroundColor: theme.codeTextColor,
                .wbCodeTokenKind: CodeTokenKind.plain.rawValue,
            ])

        let characters = Array(code)
        var index = 0

        // 扫描过程中 start/end/index 都是 Character（字位簇）偏移，但 NSMutableAttributedString
        // 的 NSRange 要的是 UTF-16 偏移。含非 BMP 字符（如 emoji）或多标量字位簇时两者不相等，
        // 直接把 Character 偏移当 NSRange 用会导致该字符之后的高亮区间整体错位。
        // 这里预先算出每个 Character 偏移对应的 UTF-16 起始偏移，apply 时做一次换算。
        // utf16Offsets[i] 表示第 i 个 Character 在 UTF-16 视图里的起始偏移，
        // 长度为 characters.count + 1，最后一个元素是整段文本的 UTF-16 总长度。
        var utf16Offsets = [Int](repeating: 0, count: characters.count + 1)
        for i in 0..<characters.count {
            utf16Offsets[i + 1] = utf16Offsets[i] + characters[i].utf16.count
        }

        func apply(_ kind: CodeTokenKind, from start: Int, to end: Int) {
            guard end > start else { return }
            let location = utf16Offsets[start]
            let length = utf16Offsets[end] - location
            result.addAttributes([
                .foregroundColor: Self.color(for: kind, theme: theme),
                .wbCodeTokenKind: kind.rawValue,
            ], range: NSRange(location: location, length: length))
        }

        while index < characters.count {
            let character = characters[index]

            // 行注释：// 与 #（bash/python）
            if character == "/", index + 1 < characters.count, characters[index + 1] == "/" {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                apply(.comment, from: start, to: index)
                continue
            }
            if character == "#", normalized == "python" || normalized == "bash" {
                let start = index
                while index < characters.count, characters[index] != "\n" { index += 1 }
                apply(.comment, from: start, to: index)
                continue
            }
            // 块注释
            if character == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let start = index
                index += 2
                while index + 1 < characters.count,
                      !(characters[index] == "*" && characters[index + 1] == "/") { index += 1 }
                index = min(index + 2, characters.count)
                apply(.comment, from: start, to: index)
                continue
            }
            // 字符串
            if character == "\"" || character == "'" {
                let quote = character
                let start = index
                index += 1
                while index < characters.count {
                    // 反斜杠可能恰好是输入的最后一个字符（流式渲染下截断内容常见），
                    // 与块注释分支保持一致，用 min 防止跳过数组末尾导致越界。
                    if characters[index] == "\\" { index = min(index + 2, characters.count); continue }
                    if characters[index] == quote { index += 1; break }
                    if characters[index] == "\n" { break }
                    index += 1
                }
                apply(.string, from: start, to: index)
                continue
            }
            // 数字
            if character.isNumber {
                let start = index
                while index < characters.count,
                      characters[index].isNumber || characters[index] == "." { index += 1 }
                apply(.number, from: start, to: index)
                continue
            }
            // 标识符 / 关键字
            if character.isLetter || character == "_" || character == "@" {
                let start = index
                if characters[index] == "@" { index += 1 }
                while index < characters.count,
                      characters[index].isLetter || characters[index].isNumber
                        || characters[index] == "_" { index += 1 }
                let word = String(characters[start..<index])
                if keywords.contains(word) {
                    apply(.keyword, from: start, to: index)
                }
                continue
            }
            // 其余符号原样保留
            index += 1
        }
        return result
    }

    private static func color(for kind: CodeTokenKind, theme: MarkdownTheme) -> UIColor {
        switch kind {
        case .keyword: return UIColor.systemPink
        case .string:  return UIColor.systemRed
        case .comment: return theme.secondaryColor
        case .number:  return UIColor.systemBlue
        case .plain:   return theme.codeTextColor
        }
    }
}
