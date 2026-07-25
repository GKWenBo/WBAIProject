import Testing
@testable import WBAppleIntelligence

struct ModelAvailabilityTests {

    @Test("可用状态的 isAvailable 为真")
    func availableIsAvailable() {
        #expect(ModelAvailability.available.isAvailable)
    }

    @Test("不可用状态的 isAvailable 为假")
    func unavailableIsNotAvailable() {
        #expect(!ModelAvailability.unavailable(.deviceNotEligible).isAvailable)
    }

    @Test("每种不可用原因都有非空的标题、说明与操作建议", arguments: [
        ModelAvailability.Reason.deviceNotEligible,
        .appleIntelligenceNotEnabled,
        .modelNotReady,
        .unknown
    ])
    func everyReasonHasCopy(_ reason: ModelAvailability.Reason) {
        #expect(!reason.title.isEmpty)
        #expect(!reason.detail.isEmpty)
        #expect(!reason.recovery.isEmpty)
    }

    @Test("四种原因的文案两两不同，避免复制粘贴时漏改")
    func reasonCopyIsDistinct() {
        let details = [
            ModelAvailability.Reason.deviceNotEligible,
            .appleIntelligenceNotEnabled,
            .modelNotReady,
            .unknown
        ].map(\.detail)
        #expect(Set(details).count == details.count)
    }
}
