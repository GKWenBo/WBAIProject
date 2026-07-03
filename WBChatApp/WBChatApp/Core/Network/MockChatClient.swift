//
//  MockChatClient.swift
//  WBChatApp
//

import Foundation

/// 未配置 API Key 时的演示数据源：按词模拟 token 级流式输出
final class MockChatClient: ChatStreaming {

    func streamChat(
        messages: [ChatMessagePayload],
        config: DeepSeekConfig
    ) -> AsyncThrowingStream<StreamChunk, Error> {
        let isReasoner = true
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if isReasoner {
                        for piece in Self.tokenize(Self.mockReasoning) {
                            try await Task.sleep(for: .milliseconds(20))
                            continuation.yield(StreamChunk(deltaReasoning: piece))
                        }
                    }
                    for piece in Self.tokenize(Self.mockAnswer) {
                        try await Task.sleep(for: .milliseconds(25))
                        continuation.yield(StreamChunk(deltaContent: piece))
                    }
                    continuation.yield(StreamChunk(finishReason: "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Private

    /// 按字符切块，模拟真实 token 粒度
    private nonisolated static func tokenize(_ text: String) -> [String] {
        var pieces: [String] = []
        var buffer = ""
        for character in text {
            buffer.append(character)
            if buffer.count >= 3 {
                pieces.append(buffer)
                buffer = ""
            }
        }
        if !buffer.isEmpty {
            pieces.append(buffer)
        }
        return pieces
    }

    private static let mockReasoning = """
    用户想了解流式输出的效果。我应该给出一段包含多种 Markdown 元素的回答，\
    覆盖标题、列表、代码块和表格，方便验证渲染效果。同时提醒用户当前处于演示模式。
    """

    private static let mockAnswer = """
    当前处于**演示模式**（尚未配置 DeepSeek API Key），以下是一段用于验证渲染效果的示例回复。

    ## Swift 快速排序示例

    ```swift
    func quickSort<T: Comparable>(_ array: [T]) -> [T] {
        guard array.count > 1 else { return array }
        let pivot = array[array.count / 2]
        return quickSort(array.filter { $0 < pivot })
            + array.filter { $0 == pivot }
            + quickSort(array.filter { $0 > pivot })
    }
    ```

    核心要点：

    - **时间复杂度**：平均 O(n log n)，最坏 O(n²)
    - **空间复杂度**：此写法 O(n)，原地分区可优化到 O(log n)
    - 属于*不稳定*排序

    | 算法 | 平均复杂度 | 稳定性 |
    | --- | --- | --- |
    | 快速排序 | O(n log n) | 不稳定 |
    | 归并排序 | O(n log n) | 稳定 |

    > 前往「设置」填入 API Key 即可接入真实的 DeepSeek 模型。
    """
}
