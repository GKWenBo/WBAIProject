import FoundationModels
import Testing
@testable import WBAppleIntelligence

struct ServiceTicketTests {

    @Test("schema 中包含全部六个字段名")
    func schemaContainsAllFields() throws {
        let description = ServiceTicket.generationSchema.debugDescription
        for field in ["title", "category", "priority", "affectedPeople", "keywords", "summary"] {
            #expect(description.contains(field), "schema 中缺少字段 \(field)")
        }
    }

    @Test("类别枚举每个 case 都有中文名", arguments: TicketCategory.allDisplayCases)
    func categoryHasDisplayName(_ category: TicketCategory) {
        #expect(!category.displayName.isEmpty)
    }

    @Test("优先级枚举每个 case 都有中文名", arguments: TicketPriority.allDisplayCases)
    func priorityHasDisplayName(_ priority: TicketPriority) {
        #expect(!priority.displayName.isEmpty)
    }

    @Test("能从 GeneratedContent 还原出完整工单")
    func decodesFromGeneratedContent() throws {
        let json = """
        {
          "title": "会议室投影仪无法连接",
          "category": "hardware",
          "priority": "medium",
          "affectedPeople": 8,
          "keywords": ["投影仪", "HDMI"],
          "summary": "三楼会议室的投影仪通过 HDMI 连接后没有信号。"
        }
        """
        let ticket = try ServiceTicket(GeneratedContent(json: json))

        #expect(ticket.title == "会议室投影仪无法连接")
        #expect(ticket.category == .hardware)
        #expect(ticket.priority == .medium)
        #expect(ticket.affectedPeople == 8)
        #expect(ticket.keywords == ["投影仪", "HDMI"])
        #expect(ticket.summary == "三楼会议室的投影仪通过 HDMI 连接后没有信号。")
    }
}
