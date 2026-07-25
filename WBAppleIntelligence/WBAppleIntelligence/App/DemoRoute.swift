import Foundation

/// 能力目录的路由。
///
/// 用枚举而不是 `AnyView` 承载导航目标，一是保证类型安全，二是让每个 Demo 的
/// 「场景 / 价值 / 所用框架」这些元信息有唯一出处，首页列表与详情页头部共用同一份数据。
enum DemoRoute: String, CaseIterable, Identifiable, Hashable {
    case availability
    case streamingChat
    case ticketExtraction
    case toolCalling

    var id: String { rawValue }

    var title: String {
        switch self {
        case .availability: "端侧可用性探测"
        case .streamingChat: "流式客服助手"
        case .ticketExtraction: "结构化工单抽取"
        case .toolCalling: "工具调用接内部系统"
        }
    }

    /// 这个能力在企业里对应的真实场景。
    var scenario: String {
        switch self {
        case .availability:
            "上线前判断当前设备能否使用端侧模型，决定走 AI 路径还是传统路径。"
        case .streamingChat:
            "内部知识客服：员工用自然语言提问，答案逐字流式呈现，全程不联网。"
        case .ticketExtraction:
            "服务台工单录入：把用户的口语描述实时抽取成强类型工单，边生成边填表。"
        case .toolCalling:
            "让模型调用库存、订单等内部系统接口，用自然语言完成原本要点五六个页面的查询。"
        }
    }

    /// 相比传统实现或云端方案的价值点。
    var value: String {
        switch self {
        case .availability:
            "端侧能力不是「有或没有」而是「按设备分布」，可用性探测是灰度策略的地基。"
        case .streamingChat:
            "对话内容不出设备，天然满足数据不出境与内部资料保密要求；无 token 费用，无网络延迟。"
        case .ticketExtraction:
            "结构化输出由 schema 强约束，解析不会失败；录入耗时从分钟级降到秒级。"
        case .toolCalling:
            "模型只拿到工具的返回值，业务数据的访问边界由你的代码控制，不需要把数据喂给云端模型。"
        }
    }

    var frameworks: String {
        "FoundationModels"
    }

    var systemImage: String {
        switch self {
        case .availability: "checkmark.seal"
        case .streamingChat: "bubble.left.and.text.bubble.right"
        case .ticketExtraction: "list.clipboard"
        case .toolCalling: "wrench.and.screwdriver"
        }
    }
}
