import Foundation
import Observation

/// 结构化抽取的状态编排。
///
/// `partial` 是流式过程中的中间态，`ticket` 是最终结果。两者都保留是有意的：
/// 界面在生成中读 `partial` 做逐字段填充，生成完读 `ticket` 展示确定结果。
@Observable
final class TicketExtractionViewModel {

    private(set) var partial: ServiceTicket.PartiallyGenerated?
    private(set) var ticket: ServiceTicket?
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isExtracting = false

    var input = TicketExtractionViewModel.sampleInput

    private let service = TicketExtractionService()

    /// 预置一段口语化描述，方便在没有键盘输入的场景下一键演示。
    static let sampleInput = """
    我们三楼会议室的投影仪今天早上开始就连不上了，HDMI 插上去没信号，\
    换了两根线都不行，笔记本是公司发的 ThinkPad X1。下午有个客户演示，\
    整个项目组八个人都等着用这个会议室。
    """

    var canExtract: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isExtracting
    }

    func reset() {
        service.reset()
        partial = nil
        ticket = nil
        metrics = .empty
        error = nil
    }

    func extract() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isExtracting else { return }

        isExtracting = true
        error = nil
        ticket = nil
        partial = nil

        do {
            let outcome = try await service.extract(from: text) { partial in
                self.partial = partial
            }
            ticket = outcome.ticket
            metrics = outcome.metrics
        } catch {
            self.error = AIKitError(error)
        }

        isExtracting = false
    }
}
