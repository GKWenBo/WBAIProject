import Foundation
import FoundationModels

/// 显式 `nonisolated`：与 AIKit 其他值类型约定一致，纯数据要能跨隔离域传递，
/// 不应被工程默认的 `@MainActor` 隔离绑住（扩展不会继承类型声明处的 nonisolated，
/// 这里没有扩展，直接标注在类型上即可）。
nonisolated struct TicketOutcome: Equatable {
    let ticket: ServiceTicket
    let metrics: GenerationMetrics
}

/// 结构化工单抽取服务。
///
/// 与自由文本对话的关键差别：`streamResponse(to:generating:)` 的每个 snapshot 给的是
/// `ServiceTicket.PartiallyGenerated`——一个所有字段都是可选值的镜像类型，
/// 已生成的字段有值、未生成的为 nil。界面据此可以做到「边生成边填表」。
@MainActor
final class TicketExtractionService {

    private var session: LanguageModelSession

    init() {
        session = LanguageModelSession(model: .default, instructions: Prompts.ticketExtraction)
    }

    func reset() {
        session = LanguageModelSession(model: .default, instructions: Prompts.ticketExtraction)
    }

    /// 抽取工单。每次字段更新都会回调 `onPartial`。
    func extract(
        from text: String,
        onPartial: (ServiceTicket.PartiallyGenerated) -> Void
    ) async throws -> TicketOutcome {
        var timer = MetricsTimer()
        var lastRawContent: GeneratedContent?

        do {
            let stream = session.streamResponse(to: text, generating: ServiceTicket.self)
            for try await snapshot in stream {
                timer.markFirstToken()
                // 留住 rawContent 而不是 content：流结束后要用它还原成完整的 ServiceTicket，
                // PartiallyGenerated 的字段全是可选值，无法直接当最终结果用。
                lastRawContent = snapshot.rawContent
                onPartial(snapshot.content)
            }
        } catch {
            throw AIKitError(error)
        }

        guard let lastRawContent else { throw AIKitError.emptyResponse }

        let ticket: ServiceTicket
        do {
            ticket = try ServiceTicket(lastRawContent)
        } catch {
            throw AIKitError(error)
        }

        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: text)
        let schemaTokens = try? await SystemLanguageModel.default.tokenCount(
            for: ServiceTicket.generationSchema
        )

        return TicketOutcome(
            ticket: ticket,
            metrics: timer.finish(
                // schema 本身也要占提示词预算，把两部分加起来才是真实的输入开销。
                promptTokenCount: sum(promptTokens, schemaTokens),
                responseTokenCount: nil
            )
        )
    }

    private func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case (let l?, let r?): l + r
        case (let l?, nil): l
        case (nil, let r?): r
        case (nil, nil): nil
        }
    }
}
