import FoundationModels

@Generable(description: "库存查询参数")
nonisolated struct InventoryQuery: Equatable, Sendable {
    @Guide(description: "物料名称或型号关键词，例如 ThinkPad、显示器、HDMI 线")
    var item: String

    @Guide(description: "仓库代码，如 SH01、BJ02。员工没有指定仓库时留空")
    var warehouse: String?
}

@Generable(description: "订单查询参数")
nonisolated struct OrderQuery: Equatable, Sendable {
    @Guide(description: "销售订单号，形如 SO-2026-0417", .pattern(#/SO-\d{4}-\d{4}/#))
    var orderID: String
}

/// 库存查询工具。
///
/// `Tool` 的 `name` 与 `includesSchemaInInstructions` 协议本身有默认实现，
/// `parameters` 在 `Arguments` 遵循 `Generable` 时也会自动合成，所以这里只需要
/// 提供 `description` 与 `call`。`description` 写得越具体，模型越不容易漏调工具。
struct InventoryLookupTool: Tool {
    typealias Arguments = InventoryQuery
    typealias Output = String

    let name = "queryInventory"
    let description = "查询指定物料在各仓库的实时库存数量。需要具体库存数字时必须调用本工具。"

    func call(arguments: InventoryQuery) async throws -> String {
        let records = MockEnterpriseBackend.shared.stock(
            forItem: arguments.item,
            warehouse: arguments.warehouse
        )

        // 查不到时返回明确说明而不是空串：空串会让模型以为工具没生效，
        // 转而凭记忆编一个数字出来。
        guard !records.isEmpty else {
            let scope = arguments.warehouse.map { "仓库 \($0)" } ?? "所有仓库"
            return "未查询到「\(arguments.item)」在\(scope)的库存记录。"
        }

        return records
            .map { "\($0.warehouse) 仓：\($0.item)，库存 \($0.quantity) 件" }
            .joined(separator: "；")
    }
}

/// 订单状态查询工具。
struct OrderStatusTool: Tool {
    typealias Arguments = OrderQuery
    typealias Output = String

    let name = "queryOrderStatus"
    let description = "按销售订单号查询订单当前状态与预计送达日期。"

    func call(arguments: OrderQuery) async throws -> String {
        guard let order = MockEnterpriseBackend.shared.order(id: arguments.orderID) else {
            return "未查询到订单 \(arguments.orderID)。请核对订单号是否正确。"
        }
        return "订单 \(order.orderID) 当前状态：\(order.status)，预计送达 \(order.expectedDelivery)。"
    }
}
