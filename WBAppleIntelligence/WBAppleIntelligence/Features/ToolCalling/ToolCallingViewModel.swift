import Foundation
import Observation

@Observable
final class ToolCallingViewModel {

    private(set) var answer: String = ""
    private(set) var toolCalls: [ToolCallRecord] = []
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isAsking = false

    var input = ""

    /// 预置问题，方便快速演示三种典型情况：命中、按仓库过滤、查不到。
    static let samples = [
        "ThinkPad 现在还有多少库存？",
        "上海仓的 HDMI 线还有货吗？",
        "订单 SO-2026-0417 到哪了？"
    ]

    private let service = ToolCallingService()

    var canAsk: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isAsking
    }

    func reset() {
        service.reset()
        answer = ""
        toolCalls = []
        metrics = .empty
        error = nil
    }

    func ask() async {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }

        isAsking = true
        error = nil
        answer = ""
        toolCalls = []

        do {
            let outcome = try await service.ask(question)
            answer = outcome.answer
            toolCalls = outcome.toolCalls
            metrics = outcome.metrics
        } catch {
            self.error = AIKitError(error)
        }

        isAsking = false
    }
}
