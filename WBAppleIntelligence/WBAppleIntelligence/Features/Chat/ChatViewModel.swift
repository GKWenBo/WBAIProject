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
/// 会话生命周期、流式响应、transcript 管理与错误映射都在 `StreamingChatService` 里完成；
/// 这里唯一接触到的模型相关类型是轻量的 `GenerationOptions` 值类型，不持有 `LanguageModelSession`
/// 或 `Transcript` 这类更重的模型状态。
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
        // 指标必须一起清掉：留着上一轮的数字，这一轮生成期间 MetricsBar 会一直显示旧值，
        // 万一这一轮还失败了，旧指标就直接排在错误提示下面，读起来像是这次失败的耗时。
        metrics = .empty
        didTrimContext = false
        isResponding = true
        messages.append(ChatMessage(role: .user, text: prompt))

        // 先插入一条空的助手消息，后续增量直接改这一条，界面上就是逐字出现的效果。
        //
        // 下面用 replyIndex 下标写入、失败时用 removeLast() 回退，都建立在同一条不变量上：
        // 整个 await 期间不会有别的代码去动 messages。这条不变量目前是靠界面保证的
        //（发送按钮与「新会话」按钮都绑了 .disabled(viewModel.isResponding)，reset() 进不来），
        // 而不是靠本类型自己拦住——如果以后新增了不受该开关约束的入口，这里要一并复查。
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
            // 撤掉这一轮的助手回复。它不一定是空的——流在中途抛错时，前面收到的增量
            // 已经写进去了；留着这半截内容比什么都不显示更糟，用户会以为那就是完整回答。
            messages.removeLast()
        }

        isResponding = false
    }
}
