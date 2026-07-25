import FoundationModels

/// 从员工的自由文本描述中抽取出的一张 IT 服务工单。
///
/// 字段顺序不是随意排的：模型按声明顺序生成，流式填表时用户看到的填充次序就是这个顺序，
/// 所以把最能立刻确认「抽对了没有」的 title 放在最前面。
///
/// `@Generable` 会为该类型合成 `generationSchema`、`PartiallyGenerated` 以及
/// `init(_ content: GeneratedContent) throws`，schema 由框架强制约束模型输出，
/// 所以这里不需要写任何 JSON 解析与容错代码。
///
/// 显式 `nonisolated`：工程开启了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，
/// 不加标注的类型会被隐式推断为 `@MainActor`，连同其协议一致性（如 `Equatable`）
/// 一起被主线程隔离，与 AIKit 其他纯值类型的约定不一致。
@Generable(description: "从员工的自由文本描述中抽取出的一张 IT 服务工单")
nonisolated struct ServiceTicket: Equatable, Sendable {

    @Guide(description: "一句话工单标题，控制在 20 个汉字以内，要具体到设备或系统")
    var title: String

    @Guide(description: "工单类别")
    var category: TicketCategory

    @Guide(description: "紧急程度")
    var priority: TicketPriority

    @Guide(description: "受影响的人数，只影响描述者本人时填 1", .minimum(1), .maximum(100_000))
    var affectedPeople: Int

    @Guide(description: "可检索的关键实体，如设备型号、系统名称、错误码，不要放形容词", .maximumCount(5))
    var keywords: [String]

    @Guide(description: "对问题的客观复述，不要添加原文没有的信息")
    var summary: String
}

@Generable(description: "工单类别")
nonisolated enum TicketCategory: Equatable, Sendable {
    case hardware
    case software
    case network
    case account
    case other
}

@Generable(description: "工单紧急程度")
nonisolated enum TicketPriority: Equatable, Sendable {
    case low
    case medium
    case high
    case urgent
}

// 扩展不会自动继承类型声明处的 nonisolated，需要单独标注。
nonisolated extension TicketCategory {
    var displayName: String {
        switch self {
        case .hardware: "硬件"
        case .software: "软件"
        case .network: "网络"
        case .account: "账号权限"
        case .other: "其他"
        }
    }

    /// 供测试与界面遍历使用。
    ///
    /// 不加 `CaseIterable`：`@Generable` 会给枚举合成成员，与 `CaseIterable` 的
    /// `allCases` 合成同时存在时容易产生歧义，手写一份反而更省心。
    static let allDisplayCases: [TicketCategory] = [.hardware, .software, .network, .account, .other]
}

nonisolated extension TicketPriority {
    var displayName: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        case .urgent: "紧急"
        }
    }

    static let allDisplayCases: [TicketPriority] = [.low, .medium, .high, .urgent]
}
