import Foundation

/// 把远端模型列表与本地推荐清单合并成设置页展示的列表。纯函数，不做 IO。
enum ModelSelectionPolicy {

    /// 设置页最多展示的模型数
    static let maxCount = 3

    /// 排序规则：
    /// 1. 本地清单中的订阅模型（远端存在），按清单顺序；
    /// 2. 本地清单中的计量模型（远端存在），按清单顺序；
    /// 3. 远端有、清单没有、且是对话模型的，按创建时间新→旧；
    /// 截取前 `maxCount` 个，结果为空时回落到本地清单。
    static func select(remote: [ModelInfo], bundled: [ModelInfo]) -> [ModelInfo] {
        let remoteByID = Dictionary(remote.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // 清单里的模型以本地标注为准，补上远端给的创建时间
        let known = bundled.compactMap { item -> ModelInfo? in
            guard let match = remoteByID[item.id] else { return nil }
            var merged = item
            merged.createdAt = match.createdAt
            if merged.displayName == nil { merged.displayName = match.displayName }
            return merged
        }
        let subscription = known.filter(\.isSubscription)
        let metered = known.filter { !$0.isSubscription }

        let bundledIDs = Set(bundled.map(\.id))
        var seen = Set<String>()
        let unknown = remote
            .filter { !bundledIDs.contains($0.id) && isChatModel($0.id) && seen.insert($0.id).inserted }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

        let result = Array((subscription + metered + unknown).prefix(maxCount))
        return result.isEmpty ? fallback(bundled) : result
    }

    /// 本地兜底：订阅优先，再截取
    static func fallback(_ bundled: [ModelInfo]) -> [ModelInfo] {
        Array((bundled.filter(\.isSubscription) + bundled.filter { !$0.isSubscription }).prefix(maxCount))
    }

    /// 排除非对话模型与带日期的快照版本。OpenAI 的 `/models` 会把语音、图像、向量等全量返回。
    static func isChatModel(_ id: String) -> Bool {
        let lowered = id.lowercased()
        let excludedKeywords = ["embedding", "tts", "whisper", "dall-e", "image", "moderation",
                                "audio", "realtime", "transcribe", "live", "search", "babbage", "davinci"]
        if excludedKeywords.contains(where: lowered.contains) { return false }
        // 形如 -2025-08-07 / -20251001 / -0613 的快照后缀
        if lowered.range(of: #"-(\d{4}-\d{2}-\d{2}|\d{8}|\d{4})$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }
}
