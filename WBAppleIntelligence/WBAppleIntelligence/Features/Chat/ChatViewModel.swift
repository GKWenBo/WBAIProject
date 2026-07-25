import Foundation
import FoundationModels
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role: Equatable { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
}

/// 流式客服助手的状态编排。
///
/// 只做三件事：把用户输入交给 service、把流式增量写回消息、把错误与指标暴露给界面。
/// 所有与 FoundationModels 打交道的逻辑都在 `StreamingChatService` 里，这里不出现任何模型 API。
@Observable
final class ChatViewModel {

    private(set) var messages: [ChatMessage] = []
    private(set) var metrics: GenerationMetrics = .empty
    private(set) var error: AIKitError?
    private(set) var isResponding = false
    /// 上一次回答是否因为上下文超限而裁剪过历史。
    private(set) var didTrimContext = false

    var input = ""
    /// 采样温度。0 更稳定可复现，1 更发散——这个滑杆是为了让人直观看到差别。
    var temperature: Double = 0.3

    private let service = StreamingChatService()

    var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isResponding
    }

    func prewarm() {
        service.prewarm()
    }

    func reset() {
        service.reset()
        messages = []
        metrics = .empty
        error = nil
        didTrimContext = false
    }

    func send() async {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }

        input = ""
        error = nil
        didTrimContext = false
        isResponding = true
        messages.append(ChatMessage(role: .user, text: prompt))

        // 先插入一条空的助手消息，后续增量直接改这一条，界面上就是逐字出现的效果。
        let replyIndex = messages.count
        messages.append(ChatMessage(role: .assistant, text: ""))

        do {
            let outcome = try await service.respond(
                to: prompt,
                options: GenerationOptions(temperature: temperature)
            ) { partial in
                messages[replyIndex].text = partial
            }
            messages[replyIndex].text = outcome.text
            metrics = outcome.metrics
            didTrimContext = outcome.didTrimContext
        } catch {
            self.error = AIKitError(error)
            messages.removeLast()   // 移除那条没能填上内容的空回复
        }

        isResponding = false
    }
}
