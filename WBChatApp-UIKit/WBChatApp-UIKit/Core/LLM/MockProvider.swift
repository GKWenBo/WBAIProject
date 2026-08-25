import Foundation

/// 未配置 API Key 时的演示模式。
/// 脚本刻意覆盖标题、段落、列表、代码块、表格，用来验证渲染管线。
final class MockProvider: ChatProvider {

    static let defaultScript = """
    ## 演示模式

    当前还没有配置 API Key，这段内容是**本地模拟**生成的，用来演示流式渲染。

    渲染管线支持这些块类型：

    - 段落与 *强调*、**加粗**、`行内代码`
    - 有序与无序列表
    - 代码块（带语法高亮）
    - 表格与分割线

    ```swift
    func greet(_ name: String) -> String {
        // 已闭合的块不会再重新排版
        return "你好，\\(name)"
    }
    ```

    | 块类型 | 是否增量 |
    | --- | --- |
    | 已闭合块 | 只解析一次 |
    | 未闭合块 | 每帧重解析 |

    ---

    去「设置」里填入 API Key 即可接入真实模型。
    """

    private let script: String
    private let chunkSize: Int
    private let delay: Duration

    init(script: String = MockProvider.defaultScript,
         chunkSize: Int = 3,
         delay: Duration = .milliseconds(20)) {
        self.script = script
        self.chunkSize = max(1, chunkSize)
        self.delay = delay
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var index = script.startIndex
                    while index < script.endIndex {
                        try Task.checkCancellation()
                        let end = script.index(index, offsetBy: chunkSize,
                                               limitedBy: script.endIndex) ?? script.endIndex
                        continuation.yield(.textDelta(String(script[index..<end])))
                        index = end
                        if delay > .zero { try await Task.sleep(for: delay) }
                    }
                    continuation.yield(.usage(TokenUsage(prompt: 0, completion: script.count)))
                    continuation.yield(.done(finishReason: "stop"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
