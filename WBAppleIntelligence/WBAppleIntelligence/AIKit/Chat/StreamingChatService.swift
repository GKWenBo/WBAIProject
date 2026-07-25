import Foundation
import FoundationModels

/// 一次流式回答的结果。
/// 值类型消息，不受项目默认 MainActor 隔离约束，可跨隔离域边界传递，与 AIKit 其他值类型保持一致。
nonisolated struct ChatOutcome: Equatable, Sendable {
    let text: String
    let metrics: GenerationMetrics
    /// 本次回答是否触发过上下文裁剪。UI 需要据此提示用户「早期对话已被裁剪」。
    let didTrimContext: Bool
}

/// 流式对话服务。
///
/// 负责三件事：会话生命周期、流式增量与指标采集、上下文超限时的自动恢复。
/// 有意不 import SwiftUI —— 这个类型可以整体复制进任何 iOS 26 工程。
@MainActor
final class StreamingChatService {

    private let instructions: String
    private let recentEntriesToKeep: Int
    private var session: LanguageModelSession

    init(instructions: String = Prompts.helpdesk, recentEntriesToKeep: Int = 4) {
        self.instructions = instructions
        self.recentEntriesToKeep = recentEntriesToKeep
        self.session = LanguageModelSession(model: .default, instructions: instructions)
    }

    /// 预热。
    ///
    /// 首次调用要把模型权重载入内存，冷启动可能到秒级；在用户还在打字时提前预热，
    /// 能把这段开销从「首字延迟」里挪走。代价是一段时间的内存占用，所以只在用户
    /// 明确进入对话界面后才调，不在 App 启动时调。
    func prewarm() {
        session.prewarm()
    }

    /// 丢弃当前会话历史，回到初始状态。
    func reset() {
        session = LanguageModelSession(model: .default, instructions: instructions)
    }

    /// 流式回答。
    ///
    /// 每收到一次增量就用**累计到当前为止的完整文本**回调 `onPartial`——
    /// FoundationModels 的 snapshot 给的是累计值而不是增量差值，UI 直接赋值即可，不要做拼接。
    func respond(
        to prompt: String,
        options: GenerationOptions = GenerationOptions(),
        onPartial: (String) -> Void
    ) async throws -> ChatOutcome {
        do {
            let result = try await streamOnce(prompt, options: options, onPartial: onPartial)
            return ChatOutcome(text: result.text, metrics: result.metrics, didTrimContext: false)
        } catch let error as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = error else {
                throw AIKitError(error)
            }
            // 上下文撑爆了：裁掉早期对话、保住系统提示，用剩下的历史重建会话后重试一次。
            // 只重试一次——如果裁剪后仍然超限，说明单次提问本身就过长，重试没有意义。
            session = LanguageModelSession(
                model: .default,
                transcript: TranscriptTrimmer.trim(
                    session.transcript,
                    keepingRecentEntries: recentEntriesToKeep
                )
            )
            do {
                let result = try await streamOnce(prompt, options: options, onPartial: onPartial)
                return ChatOutcome(text: result.text, metrics: result.metrics, didTrimContext: true)
            } catch {
                throw AIKitError(error)
            }
        } catch {
            throw AIKitError(error)
        }
    }

    private func streamOnce(
        _ prompt: String,
        options: GenerationOptions,
        onPartial: (String) -> Void
    ) async throws -> (text: String, metrics: GenerationMetrics) {
        var timer = MetricsTimer()
        var latest = ""

        for try await snapshot in session.streamResponse(to: prompt, options: options) {
            timer.markFirstToken()
            latest = snapshot.content
            onPartial(latest)
        }

        guard !latest.isEmpty else { throw AIKitError.emptyResponse }

        // token 统计失败不应该让整次回答失败，所以这里用 try? 降级为 nil。
        let promptTokens = try? await SystemLanguageModel.default.tokenCount(for: prompt)
        let responseTokens = try? await SystemLanguageModel.default.tokenCount(for: latest)

        return (latest, timer.finish(
            promptTokenCount: promptTokens,
            responseTokenCount: responseTokens
        ))
    }
}
