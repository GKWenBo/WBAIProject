import Foundation
import Testing
@testable import WBAppleIntelligence

struct AIKitErrorTests {

    @Test("非 FoundationModels 的错误被归入 underlying")
    func wrapsForeignError() {
        let foreign = NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "网络断开"])
        let error = AIKitError(foreign)
        #expect(error == .underlying("网络断开"))
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
