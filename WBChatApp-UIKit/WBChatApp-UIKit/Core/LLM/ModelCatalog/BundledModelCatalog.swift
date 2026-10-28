import Foundation

/// 本地内置的推荐模型清单：无 Key、请求失败或离线时兜底展示，
/// 同时为远端结果提供订阅标注与优先顺序。每家第一个为默认模型。
///
/// 清单依据 2026-10 各服务商官方模型文档整理；订阅标注为本地约定口径
/// （面向日常对话的主力通用模型标为订阅，偏专用或高单价模型标为计量）。
enum BundledModelCatalog {

    static func models(for provider: ProviderKind) -> [ModelInfo] {
        switch provider {
        case .deepSeek:
            return [
                ModelInfo(id: "deepseek-flash", displayName: "DeepSeek-V4.1-Flash", isSubscription: true),
                ModelInfo(id: "deepseek-v4-pro", displayName: "DeepSeek-V4-Pro", isSubscription: false),
            ]
        case .openAI:
            return [
                ModelInfo(id: "gpt-6-astra", displayName: "GPT-6 Astra", isSubscription: true),
                ModelInfo(id: "gpt-6.1-sol", displayName: "GPT-6.1 Sol", isSubscription: true),
                ModelInfo(id: "gpt-6.1-terra", displayName: "GPT-6.1 Terra", isSubscription: false),
                ModelInfo(id: "gpt-6-luna", displayName: "GPT-6 Luna", isSubscription: false),
            ]
        case .anthropic:
            return [
                ModelInfo(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5", isSubscription: true),
                ModelInfo(id: "claude-opus-5-5", displayName: "Claude Opus 5.5", isSubscription: true),
                ModelInfo(id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5", isSubscription: true),
                ModelInfo(id: "claude-fable-5-1", displayName: "Claude Fable 5.1", isSubscription: false),
            ]
        }
    }

    static func defaultModel(for provider: ProviderKind) -> String {
        models(for: provider)[0].id
    }
}
