import Foundation
import FoundationModels
import Testing
@testable import WBAppleIntelligence

struct AIKitErrorTests {

    @Test("非 FoundationModels 的错误被归入 underlying")
    func wrapsForeignError() {
        let foreign = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "网络断开"])
        let error = AIKitError(foreign)
        #expect(error == .underlying("网络断开"))
    }

    /// `GenerationError` 未标注 Sendable，不能直接塞进 `@Test(arguments:)`；
    /// 改用这个可 Sendable 的标签枚举驱动参数化，测试体内再各自构造真实的框架错误值。
    enum GenerationErrorTag: String, CaseIterable {
        case exceededContextWindowSize
        case assetsUnavailable
        case guardrailViolation
        case unsupportedGuide
        case unsupportedLanguageOrLocale
        case decodingFailure
        case rateLimited
        case concurrentRequests
        case refusal
    }

    /// `GenerationError` 是非 frozen 枚举，九个 case 逐一构造真实值送入 `AIKitError(_:)`，
    /// 直接锁定 switch 里的映射关系——防止未来有人手滑把两个分支顺序换错却没人发现。
    @Test("GenerationError 九种 case 逐一映射到期望的 AIKitError", arguments: GenerationErrorTag.allCases)
    func mapsEveryGenerationErrorCase(_ tag: GenerationErrorTag) {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "诊断信息")
        let generation: LanguageModelSession.GenerationError
        let expected: AIKitError
        switch tag {
        case .exceededContextWindowSize:
            generation = .exceededContextWindowSize(context)
            expected = .contextWindowExceeded
        case .assetsUnavailable:
            generation = .assetsUnavailable(context)
            expected = .assetsUnavailable
        case .guardrailViolation:
            generation = .guardrailViolation(context)
            expected = .guardrailViolation
        case .unsupportedGuide:
            generation = .unsupportedGuide(context)
            expected = .unsupportedGuide(context.debugDescription)
        case .unsupportedLanguageOrLocale:
            generation = .unsupportedLanguageOrLocale(context)
            expected = .unsupportedLanguage
        case .decodingFailure:
            generation = .decodingFailure(context)
            expected = .decodingFailure(context.debugDescription)
        case .rateLimited:
            generation = .rateLimited(context)
            expected = .rateLimited
        case .concurrentRequests:
            generation = .concurrentRequests(context)
            expected = .concurrentRequests
        case .refusal:
            let refusal = LanguageModelSession.GenerationError.Refusal(transcriptEntries: [])
            generation = .refusal(refusal, context)
            expected = .refused
        }
        #expect(AIKitError(generation) == expected)
    }

    @Test("已经是 AIKitError 时原样返回，不会被重复包一层")
    func doesNotDoubleWrap() {
        let original = AIKitError.contextWindowExceeded
        #expect(AIKitError(original) == original)
    }

    @Test("每个 case 都有非空的描述与恢复建议", arguments: AIKitError.allCasesForCopyCheck)
    func everyCaseHasCopy(_ error: AIKitError) {
        #expect(!(error.errorDescription ?? "").isEmpty)
        #expect(!(error.recoverySuggestion ?? "").isEmpty)
    }

    @Test("上下文超限的建议里要明确提到会裁剪早期对话，避免用户以为数据丢了")
    func contextWindowCopyMentionsTrimming() {
        let suggestion = AIKitError.contextWindowExceeded.recoverySuggestion ?? ""
        #expect(suggestion.contains("裁剪"))
    }
}
