import Foundation
import FoundationModels

/// AIKit 的统一错误域。
///
/// 存在的意义是把 `LanguageModelSession.GenerationError` 这类框架错误一次性翻译成
/// 「用户看得懂的描述 + 能照做的建议」，避免每个 Demo 各写一遍 switch。
/// `GenerationError` 是非 frozen 枚举，映射集中在这里也便于系统升级时统一兜底。
///
/// 显式 `nonisolated`：原因同 `ModelAvailability`——本类型会在非隔离上下文
/// （如后台 actor、`Tool.call` 之类的 nonisolated 协议要求）里被直接构造与比较，
/// 关联值又持有 `ModelAvailability.Reason`，若不退出默认的 `@MainActor` 隔离，
/// 合成的 `Equatable` 会在跨隔离域使用时触发编译器警告（Swift 6 下为错误）。
nonisolated enum AIKitError: LocalizedError, Equatable {
    case modelUnavailable(ModelAvailability.Reason)
    case contextWindowExceeded
    case guardrailViolation
    case unsupportedLanguage
    case assetsUnavailable
    case rateLimited
    case concurrentRequests
    case refused
    case decodingFailure(String)
    case unsupportedGuide(String)
    /// 流式响应一个增量都没产生就结束了。
    case emptyResponse
    case underlying(String)

    init(_ error: any Error) {
        if let alreadyMapped = error as? AIKitError {
            self = alreadyMapped
            return
        }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            self = .underlying(error.localizedDescription)
            return
        }
        switch generation {
        case .exceededContextWindowSize:
            self = .contextWindowExceeded
        case .guardrailViolation:
            self = .guardrailViolation
        case .unsupportedLanguageOrLocale:
            self = .unsupportedLanguage
        case .assetsUnavailable:
            self = .assetsUnavailable
        case .rateLimited:
            self = .rateLimited
        case .concurrentRequests:
            self = .concurrentRequests
        case .refusal:
            self = .refused
        case .decodingFailure(let context):
            self = .decodingFailure(context.debugDescription)
        case .unsupportedGuide(let context):
            self = .unsupportedGuide(context.debugDescription)
        @unknown default:
            self = .underlying(generation.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason): reason.title
        case .contextWindowExceeded: "对话内容超出了模型的上下文窗口"
        case .guardrailViolation: "内容被安全护栏拦截"
        case .unsupportedLanguage: "当前语言或地区不受支持"
        case .assetsUnavailable: "模型资源不可用"
        case .rateLimited: "请求过于频繁"
        case .concurrentRequests: "上一次生成尚未结束"
        case .refused: "模型拒绝回答本次请求"
        case .decodingFailure: "模型输出无法解析成目标结构"
        case .unsupportedGuide: "结构定义中存在模型不支持的约束"
        case .emptyResponse: "模型没有返回任何内容"
        case .underlying(let message): message
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .modelUnavailable(let reason):
            reason.recovery
        case .contextWindowExceeded:
            "已自动裁剪早期对话后重试。若仍失败，请开启新会话——端侧模型上下文窗口仅 4096 token，长对话必须做裁剪。"
        case .guardrailViolation:
            "请调整措辞后重试。若这是正常业务内容被误拦，可考虑改用 permissiveContentTransformations 护栏级别。"
        case .unsupportedLanguage:
            "请把设备语言切换到模型支持的语言，或改用不依赖端侧模型的路径。"
        case .assetsUnavailable:
            "请检查网络与存储空间，等待系统完成模型下载后重试。"
        case .rateLimited:
            "请稍后再试。App 进入后台时系统会更严格地限流。"
        case .concurrentRequests:
            "请等待当前回答结束，或先取消当前生成。同一个会话不支持并发请求。"
        case .refused:
            "请换一种说法重试。可通过 refusal 的 explanation 获取模型给出的拒绝理由。"
        case .decodingFailure(let detail):
            "请简化结构定义或降低字段数量后重试。诊断信息：\(detail)"
        case .unsupportedGuide(let detail):
            "请检查 @Guide 约束是否被当前模型支持。诊断信息：\(detail)"
        case .emptyResponse:
            "请重试一次；若持续为空，请检查提示词是否为空或过短。"
        case .underlying:
            "请重试；若持续失败，请查看日志中的原始错误信息。"
        }
    }
}

// 扩展不会自动继承类型声明处的 nonisolated，需要单独标注。
nonisolated extension AIKitError {
    /// 供测试遍历文案完整性使用。手写而非依赖 `CaseIterable`，
    /// 因为带关联值的 case 无法自动合成。
    static let allCasesForCopyCheck: [AIKitError] = [
        .modelUnavailable(.deviceNotEligible),
        .contextWindowExceeded,
        .guardrailViolation,
        .unsupportedLanguage,
        .assetsUnavailable,
        .rateLimited,
        .concurrentRequests,
        .refused,
        .decodingFailure("测试诊断"),
        .unsupportedGuide("测试诊断"),
        .emptyResponse,
        .underlying("测试原因")
    ]
}
