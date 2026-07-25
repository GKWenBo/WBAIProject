import FoundationModels

/// Transcript 裁剪策略。
///
/// 端侧模型的上下文窗口只有 4096 token，长会话必然会撞上 `exceededContextWindowSize`。
/// 恢复办法是从旧会话的 Transcript 里挑出该留的条目重建一个新会话。
///
/// 之所以做成不依赖会话的纯函数：裁剪策略是最容易出错也最需要回归测试的一环，
/// 剥离掉 `LanguageModelSession` 之后它就能被完全确定性地单测。
nonisolated enum TranscriptTrimmer {

    /// 保留首条 instructions（若有）与最近 `count` 条其他条目。
    ///
    /// instructions 必须钉住：它是模型的角色设定，裁掉之后模型行为会当场跑偏。
    /// 只钉第一条是因为一个会话的系统提示只应该有一份，后面出现的同类条目按普通条目处理。
    static func trim(_ transcript: Transcript, keepingRecentEntries count: Int) -> Transcript {
        var pinnedInstructions: [Transcript.Entry] = []
        var others: [Transcript.Entry] = []

        for entry in transcript {
            if case .instructions = entry, pinnedInstructions.isEmpty {
                pinnedInstructions.append(entry)
            } else {
                others.append(entry)
            }
        }

        let keep = max(0, count)
        return Transcript(entries: pinnedInstructions + others.suffix(keep))
    }
}
