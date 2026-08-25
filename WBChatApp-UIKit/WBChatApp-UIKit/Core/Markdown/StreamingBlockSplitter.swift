import Foundation

/// 流式 Markdown 块切分器。
///
/// 设计要点：
/// 1. **只处理完整行。** 尾部那段还没等到换行符的文本永远留在 `partial` 里，
///    连同它所属的块一起以 open 形式输出。这保证了已闭合的块不可能再变。
/// 2. **核心不变量：** `sealedBlocks` 随流推进只增不改。
///    上层据此把已闭合块的属性串与高度永久缓存，从而把总代价从 O(n²) 降到 O(n)。
/// 3. 纯值语义、无 UI 依赖，可以逐字符喂入做属性测试。
struct StreamingBlockSplitter {

    /// 已闭合的块，只增不改
    private(set) var sealedBlocks: [MarkdownBlock] = []

    /// 当前正在累积、尚未闭合的块
    private var current: (kind: MarkdownBlockKind, lines: [String])?

    /// 列表内部遇到的空行。若后续仍是列表项就并回列表，否则丢弃并闭合列表。
    private var pendingBlankLines: [String] = []

    /// 还没等到换行符的尾部文本
    private var partial: String = ""

    private var nextOrdinal: Int = 0

    init() {}

    // MARK: - 对外接口

    /// 追加一段增量文本，返回本次产生的变化。
    mutating func append(_ delta: String) -> BlockPatch {
        partial += delta
        var newlySealed: [MarkdownBlock] = []

        while let terminator = nextLineTerminator() {
            let line = String(partial[partial.startIndex..<terminator.lineEnd])
            partial = String(partial[terminator.nextStart...])
            newlySealed += consume(line)
        }
        return BlockPatch(newlySealed: newlySealed, open: openBlock)
    }

    /// 流结束。把残留的尾行与未闭合块一并闭合。
    mutating func finish() -> BlockPatch {
        var newlySealed: [MarkdownBlock] = []
        // 流已经结束：之前因无法判断「单独 CR」还是「CRLF 前半」而被
        // nextLineTerminator() 挂起的末尾孤立 \r，此刻可以确定就是行终止符，
        // 不能再把它当普通字符留在最后一行内容里。
        if let lastScalar = partial.unicodeScalars.last, lastScalar == "\r" {
            let line = String(partial.dropLast())
            partial = ""
            newlySealed += consume(line)
        } else if !partial.isEmpty {
            let line = partial
            partial = ""
            newlySealed += consume(line)
        }
        if current != nil {
            newlySealed.append(seal())
        }
        return BlockPatch(newlySealed: newlySealed, open: nil)
    }

    /// 已闭合块 + 当前未闭合块
    var allBlocks: [MarkdownBlock] {
        if let open = openBlock { return sealedBlocks + [open] }
        return sealedBlocks
    }

    // MARK: - 行切分

    private struct LineTerminator {
        let lineEnd: String.Index
        let nextStart: String.Index
    }

    private func nextLineTerminator() -> LineTerminator? {
        // 用 unicodeScalars 而非 Character 视图查找：Swift 的字位簇规则（GB3）会把
        // 相邻的 \r\n 合并成同一个 Character，无论它们是一次性写入的同一个字符串，
        // 还是被两次 append 拼接到一起——`partial += delta` 拼接后会重新计算字位簇边界。
        // 合并后的 "\r\n" 既不等于单独的 "\n" 也不等于单独的 "\r"，
        // 按 Character 比较会导致这个换行永远找不到。unicodeScalars 与 String 共用
        // 同一套 String.Index，直接切片安全，且天然不做这种合并。
        let scalars = partial.unicodeScalars
        guard let index = scalars.firstIndex(where: { $0 == "\n" || $0 == "\r" }) else {
            return nil
        }
        if scalars[index] == "\r" {
            let next = scalars.index(after: index)
            // 落在末尾的 \r 要等下一个字符才能判断是 CR 还是 CRLF
            if next == scalars.endIndex { return nil }
            if scalars[next] == "\n" {
                return LineTerminator(lineEnd: index, nextStart: scalars.index(after: next))
            }
        }
        return LineTerminator(lineEnd: index, nextStart: scalars.index(after: index))
    }

    // MARK: - 块状态机

    /// 吃掉一整行，返回本行导致闭合的块。
    private mutating func consume(_ line: String) -> [MarkdownBlock] {
        var sealed: [MarkdownBlock] = []
        var lineToProcess: String? = line

        // 一行最多触发一次「闭合旧块 + 重新处理该行」，用循环而非递归表达
        while let currentLine = lineToProcess {
            lineToProcess = nil
            let isBlank = currentLine.trimmingCharacters(in: .whitespaces).isEmpty

            guard var block = current else {
                if isBlank { break }
                let kind = Self.kind(ofOpeningLine: currentLine)
                current = (kind, [currentLine])
                if kind.sealsOnSingleLine { sealed.append(seal()) }
                break
            }

            switch block.kind {
            case .codeFence:
                block.lines.append(currentLine)
                current = block
                if Self.isClosingFence(currentLine, opener: block.lines[0]) {
                    sealed.append(seal())
                }

            case .blockQuote:
                if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    block.lines.append(currentLine)
                    current = block
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .table:
                if currentLine.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    block.lines.append(currentLine)
                    current = block
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .list(let ordered):
                if isBlank {
                    // 先挂起，等下一行决定这是列表内的空行还是列表结束
                    pendingBlankLines.append(currentLine)
                } else if Self.isIndentedContinuation(currentLine) {
                    block.lines += pendingBlankLines
                    pendingBlankLines.removeAll()
                    block.lines.append(currentLine)
                    current = block
                } else if Self.isListItem(currentLine) {
                    let itemIsOrdered = Self.isOrderedListItem(currentLine.trimmingCharacters(in: .whitespaces))
                    if itemIsOrdered == ordered {
                        block.lines += pendingBlankLines
                        pendingBlankLines.removeAll()
                        block.lines.append(currentLine)
                        current = block
                    } else {
                        // 有序/无序标记切换（如 "- a" 后接 "1. x"）算作新列表的开始
                        sealed.append(seal())
                        lineToProcess = currentLine
                    }
                } else {
                    sealed.append(seal())
                    lineToProcess = currentLine
                }

            case .paragraph:
                // 段落是单行块：不管接下来是空行、其它块类型的起始行，
                // 还是又一行普通文本，都会让当前段落立刻闭合，该行交回外层重新处理。
                // 段落的"最后一行"之所以能看起来还在增长，只是因为它还没等到
                // 换行符、仍停留在 partial 里、以 open 状态呈现——一旦成为完整行，
                // 就说明上一行已经写完，必须立刻闭合（这样才能尽早进缓存）。
                sealed.append(seal())
                lineToProcess = currentLine

            case .heading, .thematicBreak:
                // 这两类在开块时已立即闭合，理论上到不了这里
                sealed.append(seal())
                lineToProcess = currentLine
            }
        }
        return sealed
    }

    private mutating func seal() -> MarkdownBlock {
        guard let block = current else {
            preconditionFailure("seal 只能在存在未闭合块时调用")
        }
        let sealed = MarkdownBlock(ordinal: nextOrdinal,
                                   kind: block.kind,
                                   rawText: block.lines.joined(separator: "\n"),
                                   isSealed: true)
        sealedBlocks.append(sealed)
        nextOrdinal += 1
        current = nil
        pendingBlankLines.removeAll()
        return sealed
    }

    /// 当前未闭合块 = 已累积的完整行 + 挂起的空行 + 尾部残行
    private var openBlock: MarkdownBlock? {
        if let block = current {
            var lines = block.lines + pendingBlankLines
            if !partial.isEmpty { lines.append(partial) }
            return MarkdownBlock(ordinal: nextOrdinal,
                                 kind: block.kind,
                                 rawText: lines.joined(separator: "\n"),
                                 isSealed: false)
        }
        guard !partial.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return MarkdownBlock(ordinal: nextOrdinal,
                             kind: Self.kind(ofOpeningLine: partial),
                             rawText: partial,
                             isSealed: false)
    }

    // MARK: - 行特征判定

    static func kind(ofOpeningLine line: String) -> MarkdownBlockKind {
        let text = line.trimmingCharacters(in: .whitespaces)

        if let fence = fenceInfo(text) {
            return .codeFence(language: fence.language)
        }
        if let level = headingLevel(text) {
            return .heading(level: level)
        }
        if isThematicBreak(text) {
            return .thematicBreak
        }
        if text.hasPrefix(">") {
            return .blockQuote
        }
        if isListItem(text) {
            return .list(ordered: isOrderedListItem(text))
        }
        if text.hasPrefix("|") {
            return .table
        }
        return .paragraph
    }

    /// 除段落外的所有块起始，都能在无空行的情况下打断上一个段落
    static func startsNewBlock(_ line: String) -> Bool {
        kind(ofOpeningLine: line) != .paragraph
    }

    private static func fenceInfo(_ text: String) -> (marker: Character, count: Int, language: String?)? {
        guard let first = text.first, first == "`" || first == "~" else { return nil }
        let count = text.prefix(while: { $0 == first }).count
        guard count >= 3 else { return nil }
        let rest = String(text.dropFirst(count)).trimmingCharacters(in: .whitespaces)
        return (first, count, rest.isEmpty ? nil : rest)
    }

    static func isClosingFence(_ line: String, opener: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let open = fenceInfo(opener.trimmingCharacters(in: .whitespaces)),
              let close = fenceInfo(text) else { return false }
        // 闭合围栏必须同字符、不短于开栏，且后面没有语言标识
        return close.marker == open.marker
            && close.count >= open.count
            && close.language == nil
    }

    private static func headingLevel(_ text: String) -> Int? {
        let hashes = text.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = text.dropFirst(hashes)
        // "#标题" 不算标题，必须有空格或整行只有 #
        guard rest.isEmpty || rest.first == " " else { return nil }
        return hashes
    }

    private static func isThematicBreak(_ text: String) -> Bool {
        let stripped = text.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" }
            || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    static func isListItem(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespaces)
        if let first = text.first, "-*+".contains(first) {
            // 必须是「标记 + 空格」，这样 "---" 不会被当成列表
            return text.dropFirst().first == " "
        }
        return isOrderedListItem(text)
    }

    private static func isOrderedListItem(_ text: String) -> Bool {
        let digits = text.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = text.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" else { return false }
        return rest.dropFirst().first == " "
    }

    /// 列表项的缩进续行
    static func isIndentedContinuation(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }
}
