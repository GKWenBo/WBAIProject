import UIKit

/// 高亮的 token 分类
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

    /// 各语言关键字表；未知语言不标关键字，只处理注释/字符串/数字
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

    /// 一次扫描的结果。
    struct ScanResult {
        let attributed: NSAttributedString
        /// 最后一个**可安全切分**的位置（字符数）。
        ///
        /// 「可安全切分」= 该位置是某一行的开头，且扫描到那里时不处于任何跨行
        /// 结构内部。满足这个条件时，「从这里截断、剩余部分从零状态重新扫描」
        /// 与「整段一次扫完」的结果完全一致，上层才能据此做增量复用。
        ///
        /// 为什么不能随便挑一个换行符：块注释 `/* */` 本来就跨行；字符串遇到
        /// 行尾反斜杠时 `index += 2` 会直接跨过换行继续吃下一行。这两种情况下
        /// 的换行处切开再分别扫描，会把后半段当成普通代码，高亮就错了。
        /// 0 表示整段都没有安全切点。
        let cleanCutCharacterCount: Int
    }

    /// 只要属性串的便捷版本
    func highlight(code: String, language: String?, theme: MarkdownTheme) -> NSAttributedString {
        scan(code: code, language: language, theme: theme).attributed
    }

    /// 从零状态线性扫描一遍，产出高亮属性串与最后一个安全切点
    func scan(code: String, language: String?, theme: MarkdownTheme) -> ScanResult {
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

        // 循环顶部意味着「不在任何 token 内部」。此时若正好站在某一行的开头，
        // 这里就是一个安全切点——跨行的块注释与反斜杠续行字符串都不会在这个
        // 位置把控制流交回循环顶部，所以它们天然不会被误判成安全的。
        var cleanCut = 0

        while index < characters.count {
            let character = characters[index]
            if index > 0, characters[index - 1] == "\n" { cleanCut = index }

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
        return ScanResult(attributed: result, cleanCutCharacterCount: cleanCut)
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
