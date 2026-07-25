import FoundationModels

/// 端侧模型可用性的领域表示。
///
/// 把 `SystemLanguageModel.Availability` 翻译成可以直接呈现给用户的中文说明与操作建议。
/// 单独建这层是因为：`UnavailableReason` 是非 frozen 枚举，系统升级可能新增 case，
/// 集中在这里加 `@unknown default` 兜底，业务代码就不必到处处理未知情况。
///
/// 显式 `nonisolated`：工程开启了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，
/// 不加标注的类型会被隐式推断为 `@MainActor`，连同其协议一致性（如 `Equatable`）
/// 一起被主线程隔离。AIKit 是不依赖 UI 的纯逻辑层，需要能在 actor、后台任务等
/// 非隔离上下文里被直接使用，因此这里主动退出默认隔离；否则合成的 `Equatable`
/// 在跨隔离域调用时会触发编译器警告，且在 Swift 6 语言模式下会变成编译错误。
nonisolated enum ModelAvailability: Equatable, Sendable {
    case available
    case unavailable(Reason)

    nonisolated enum Reason: Equatable, Hashable, CaseIterable, Sendable {
        /// 机型不满足要求，或设备区域 / 系统语言不在 Apple Intelligence 支持范围内。
        case deviceNotEligible
        /// 机型支持，但用户尚未在系统设置中开启 Apple Intelligence。
        case appleIntelligenceNotEnabled
        /// 已开启，但模型资源仍在下载或尚未就绪。
        case modelNotReady
        /// SDK 未来新增的原因。
        case unknown
    }

    init(_ availability: SystemLanguageModel.Availability) {
        switch availability {
        case .available:
            self = .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                self = .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                self = .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                self = .unavailable(.modelNotReady)
            @unknown default:
                self = .unavailable(.unknown)
            }
        }
    }

    var isAvailable: Bool {
        self == .available
    }
}

// 扩展不会自动继承类型声明处的 nonisolated；每个扩展仍受工程默认隔离规则约束，
// 所以这里也要显式标注，否则这些计算属性会被单独推断为 @MainActor。
nonisolated extension ModelAvailability.Reason {
    var title: String {
        switch self {
        case .deviceNotEligible: "此设备不支持端侧模型"
        case .appleIntelligenceNotEnabled: "尚未开启 Apple Intelligence"
        case .modelNotReady: "模型尚未就绪"
        case .unknown: "端侧模型当前不可用"
        }
    }

    var detail: String {
        switch self {
        case .deviceNotEligible:
            "需要 iPhone 15 Pro 及以上机型，且设备区域与系统语言需在 Apple Intelligence 支持范围内。中国大陆区域目前不在支持范围内。"
        case .appleIntelligenceNotEnabled:
            "设备支持端侧模型，但用户还没有在系统设置里打开 Apple Intelligence 开关。"
        case .modelNotReady:
            "开关已打开，但模型文件仍在下载或正在准备中。模型体积以 GB 计，首次启用需要时间与网络。"
        case .unknown:
            "系统返回了当前 App 尚未识别的不可用原因，可能来自更高版本的系统。"
        }
    }

    /// 给用户的下一步操作建议。企业 App 里这段文案直接决定了工单量。
    var recovery: String {
        switch self {
        case .deviceNotEligible:
            "请在支持的机型上使用，或继续使用不依赖端侧模型的常规功能。"
        case .appleIntelligenceNotEnabled:
            "请前往「设置 → Apple 智能与 Siri」开启 Apple Intelligence。"
        case .modelNotReady:
            "请保持网络连接并接入电源，稍后重试。"
        case .unknown:
            "请稍后重试；若持续出现，请升级 App 到最新版本。"
        }
    }
}
