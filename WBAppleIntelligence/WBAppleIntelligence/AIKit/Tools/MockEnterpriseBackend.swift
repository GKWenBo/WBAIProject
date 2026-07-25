import Foundation

/// 模拟企业内部系统的数据源。
///
/// 真实项目里这一层背后是 HTTP 客户端或本地数据库；这里用确定性的内存数据，
/// 好处是 Demo 完全离线可跑、单测可以直接断言具体数值。
///
/// 显式标 `nonisolated`：工程开启了默认 MainActor 隔离，而 `Tool.call` 是
/// nonisolated 的，若这里跟着默认走主线程隔离，工具实现里访问 `shared` 在
/// 本工程实际使用的 Swift 5 语言模式下只会产生一条警告（Swift 6 模式下才是
/// 编译错误）——真正兜底的是工程「clean build 零警告」的验收标准。
nonisolated struct MockEnterpriseBackend: Sendable {

    struct StockRecord: Equatable, Sendable {
        let item: String
        let warehouse: String
        let quantity: Int
    }

    struct OrderRecord: Equatable, Sendable {
        let orderID: String
        let status: String
        let expectedDelivery: String
    }

    static let shared = MockEnterpriseBackend()

    private let stockRecords: [StockRecord] = [
        StockRecord(item: "ThinkPad X1 Carbon", warehouse: "SH01", quantity: 42),
        StockRecord(item: "ThinkPad X1 Carbon", warehouse: "BJ02", quantity: 7),
        StockRecord(item: "ThinkPad T14", warehouse: "SH01", quantity: 0),
        StockRecord(item: "Dell U2723QE 显示器", warehouse: "SH01", quantity: 15),
        StockRecord(item: "HDMI 2.1 线缆 2 米", warehouse: "BJ02", quantity: 230)
    ]

    private let orderRecords: [OrderRecord] = [
        OrderRecord(orderID: "SO-2026-0417", status: "已发货", expectedDelivery: "2026-07-28"),
        OrderRecord(orderID: "SO-2026-0392", status: "备货中", expectedDelivery: "2026-08-03"),
        OrderRecord(orderID: "SO-2026-0355", status: "已签收", expectedDelivery: "2026-07-19")
    ]

    /// 按物料名模糊查询。
    ///
    /// 用模糊匹配是刻意的：模型从用户口语里提取出的物料名往往不完整
    /// （「联想那个笔记本」→「ThinkPad」），精确匹配会大面积查不到。
    func stock(forItem item: String, warehouse: String?) -> [StockRecord] {
        stockRecords.filter { record in
            guard record.item.localizedCaseInsensitiveContains(item) else { return false }
            guard let warehouse else { return true }
            return record.warehouse.caseInsensitiveCompare(warehouse) == .orderedSame
        }
    }

    func order(id: String) -> OrderRecord? {
        orderRecords.first { $0.orderID.caseInsensitiveCompare(id) == .orderedSame }
    }
}
