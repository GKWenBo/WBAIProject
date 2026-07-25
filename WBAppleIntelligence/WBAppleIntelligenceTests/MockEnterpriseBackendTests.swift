import Testing
@testable import WBAppleIntelligence

struct MockEnterpriseBackendTests {

    private let backend = MockEnterpriseBackend.shared

    @Test("按物料名模糊查询能命中")
    func findsStockByFuzzyItemName() {
        let records = backend.stock(forItem: "ThinkPad", warehouse: nil)
        #expect(!records.isEmpty)
        #expect(records.allSatisfy { $0.item.contains("ThinkPad") })
    }

    @Test("物料名大小写不敏感")
    func itemNameIsCaseInsensitive() {
        let lower = backend.stock(forItem: "thinkpad", warehouse: nil)
        let upper = backend.stock(forItem: "THINKPAD", warehouse: nil)
        #expect(lower == upper)
        #expect(!lower.isEmpty)
    }

    @Test("指定仓库时只返回该仓库的记录")
    func filtersByWarehouse() {
        let all = backend.stock(forItem: "ThinkPad", warehouse: nil)
        let shanghai = backend.stock(forItem: "ThinkPad", warehouse: "SH01")
        #expect(shanghai.count < all.count)
        #expect(shanghai.allSatisfy { $0.warehouse == "SH01" })
    }

    @Test("查不到的物料返回空数组而不是崩溃")
    func unknownItemReturnsEmpty() {
        #expect(backend.stock(forItem: "不存在的物料", warehouse: nil).isEmpty)
    }

    @Test("按订单号能查到订单")
    func findsOrder() {
        #expect(backend.order(id: "SO-2026-0417") != nil)
    }

    @Test("订单号大小写不敏感")
    func orderIDIsCaseInsensitive() {
        #expect(backend.order(id: "so-2026-0417") != nil)
    }

    @Test("查不到的订单返回 nil")
    func unknownOrderReturnsNil() {
        #expect(backend.order(id: "SO-0000-0000") == nil)
    }

    @Test("库存工具查得到时返回含数量的中文描述")
    func inventoryToolReturnsReadableText() async throws {
        let tool = InventoryLookupTool()
        let output = try await tool.call(arguments: InventoryQuery(item: "ThinkPad", warehouse: "SH01"))
        #expect(output.contains("SH01"))
        #expect(output.contains("件"))
    }

    @Test("库存工具查不到时给出明确说明，而不是返回空串让模型自由发挥")
    func inventoryToolExplainsMiss() async throws {
        let tool = InventoryLookupTool()
        let output = try await tool.call(arguments: InventoryQuery(item: "不存在的物料", warehouse: nil))
        #expect(output.contains("未查询到"))
    }

    @Test("订单工具查不到时给出明确说明")
    func orderToolExplainsMiss() async throws {
        let tool = OrderStatusTool()
        let output = try await tool.call(arguments: OrderQuery(orderID: "SO-0000-0000"))
        #expect(output.contains("未查询到"))
    }
}
