import Foundation

/// 设置页可选的一个模型。远端接口只给出 id 与创建时间，
/// 订阅属性由本地推荐清单标注（官方 `/models` 不返回计费类型）。
struct ModelInfo: Codable, Equatable, Sendable {
    let id: String
    /// 服务商给的展示名，可能为空
    var displayName: String?
    /// 是否订阅（非计量）模型，排序时优先
    var isSubscription: Bool
    /// 远端返回的创建时间，用于未收录模型按新→旧排序
    var createdAt: Date?

    init(id: String, displayName: String? = nil, isSubscription: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.isSubscription = isSubscription
        self.createdAt = createdAt
    }
}

/// 一次远端拉取的结果
struct RemoteModelCatalog: Equatable, Sendable {
    /// 排序截取后用于展示的推荐模型（最多 3 个）
    let recommended: [ModelInfo]
    /// 远端返回的全部模型 id，用于判断当前选中的模型是否已下线
    let allIDs: Set<String>
}
