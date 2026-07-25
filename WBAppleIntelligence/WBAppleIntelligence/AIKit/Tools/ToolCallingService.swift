import Foundation
import FoundationModels

/// 一次工具调用的记录，用于在界面上展示模型到底调了什么、拿到了什么。
nonisolated struct ToolCallRecord: Identifiable, Equatable {
    let id: String
    let toolName: String
    let output: String
}

nonisolated struct ToolCallOutcome: Equatable {
    let answer: String
    let toolCalls: [ToolCallRecord]
    let metrics: GenerationMetrics
}

/// 带工具的会话服务。
///
/// 工具调用是自动的：把 tools 交给 session 之后，模型自行决定何时调用、调用哪个、
/// 传什么参数，框架负责执行 `call` 并把结果回灌给模型。你的代码不需要写调度逻辑。
///
/// 这里额外做的一件事是从 `Transcript` 里把工具调用轨迹翻出来展示——
/// 企业场景里「模型到底查了什么」是必须可审计的，不能是黑箱。
@MainActor
final class ToolCallingService {

    private var session: LanguageModelSession

    init() {
        session = Self.makeSession()
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(
            model: .default,
            tools: [InventoryLookupTool(), OrderStatusTool()],
            instructions: Prompts.toolCalling
        )
    }

    func reset() {
        session = Self.makeSession()
    }

    func ask(_ question: String) async throws -> ToolCallOutcome {
        // 这里用 let 而不是 var：非流式调用不需要 markFirstToken，
        // 声明成 var 会触发「变量从未被修改」的编译器告警。
        let timer = MetricsTimer()

        let response: LanguageModelSession.Response<String>
        do {
            response = try await session.respond(to: question)
        } catch {
            throw AIKitError(error)
        }

        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: question)
        let answerTokens = try? await SystemLanguageModel.default.tokenCount(for: response.content)

        return ToolCallOutcome(
            answer: response.content,
            toolCalls: Self.toolCalls(in: response.transcriptEntries),
            metrics: timer.finish(
                promptTokenCount: promptTokens,
                responseTokenCount: answerTokens
            )
        )
    }

    /// 从本次响应产生的 Transcript 条目里提取工具输出。
    ///
    /// 只看 `.toolOutput` 而不看 `.toolCalls`：前者同时带着工具名与实际返回内容，
    /// 一条就能说明「调了谁、拿回什么」，展示所需的信息更完整。
    private static func toolCalls(
        in entries: ArraySlice<Transcript.Entry>
    ) -> [ToolCallRecord] {
        entries.compactMap { entry in
            guard case .toolOutput(let output) = entry else { return nil }
            let text = output.segments
                .compactMap { segment -> String? in
                    if case .text(let textSegment) = segment { return textSegment.content }
                    return nil
                }
                .joined(separator: "\n")
            return ToolCallRecord(id: output.id, toolName: output.toolName, output: text)
        }
    }
}
