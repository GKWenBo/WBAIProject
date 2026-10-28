//
//  StreamingTextSource.swift
//  TextKitExample
//
//  案例 9 / 10：把一段完整文本切成一小块一小块，模拟流式输出
//

import Foundation

/// 模拟流式输出的文本源：每次 `next()` 吐出一小块，直到吐完。
///
/// 块的大小按一个固定序列循环，而不是随机 —— 模拟 token 长短不一，
/// 同时保证每次运行、每次测试的切分结果都一样。
///
/// 按 `Character`（字素簇）切分，emoji、组合字符不会被从中间劈开；
/// 真实的网络流不保证这一点，接入时要在解码层处理半个字符的情况。
struct StreamingTextSource {

    let text: String
    /// 块大小序列，单位是字符（Character）。
    let chunkPattern: [Int]

    private var cursor: String.Index
    private var chunkIndex = 0

    init(text: String, chunkPattern: [Int] = [3, 1, 4, 2, 5, 2, 6]) {
        precondition(!chunkPattern.isEmpty && chunkPattern.allSatisfy { $0 > 0 },
                     "块大小序列不能为空，且每一项都要大于 0")
        self.text = text
        self.chunkPattern = chunkPattern
        self.cursor = text.startIndex
    }

    /// 是否已经吐完。
    var isFinished: Bool { cursor == text.endIndex }

    /// 已经吐出的部分。
    var emitted: Substring { text[..<cursor] }

    /// 下一块；吐完后返回 `nil`。
    mutating func next() -> String? {
        guard !isFinished else { return nil }

        let size = chunkPattern[chunkIndex % chunkPattern.count]
        chunkIndex += 1

        let end = text.index(cursor, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
        defer { cursor = end }
        return String(text[cursor..<end])
    }

    /// 回到开头。
    mutating func reset() {
        cursor = text.startIndex
        chunkIndex = 0
    }
}
