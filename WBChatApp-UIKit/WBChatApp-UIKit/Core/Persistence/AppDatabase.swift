import Foundation
import GRDB

/// SQLite 数据库的创建位置与表结构迁移
enum AppDatabase {

    /// `url` 传 nil 建内存库，供测试使用。
    static func makeQueue(at url: URL?) throws -> DatabaseQueue {
        var configuration = Configuration()
        // 外键约束默认开启，级联删除才会生效
        configuration.foreignKeysEnabled = true

        let queue: DatabaseQueue
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            queue = try DatabaseQueue(path: url.path, configuration: configuration)
        } else {
            queue = try DatabaseQueue(configuration: configuration)
        }
        try migrator.migrate(queue)
        return queue
    }

    /// App 的默认库位置
    static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return base.appendingPathComponent("WBChatApp/chat.sqlite")
    }

    /// 按版本顺序登记迁移；已发布的迁移不能修改，只能追加
    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_创建会话与消息表") { db in
            try db.create(table: "conversation") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull()
                table.column("providerRaw", .text).notNull()
                table.column("model", .text).notNull()
                table.column("createdAt", .double).notNull()
                table.column("updatedAt", .double).notNull()
            }

            try db.create(table: "message") { table in
                table.primaryKey("id", .text)
                table.column("conversationId", .text).notNull()
                    .references("conversation", onDelete: .cascade)
                table.column("ordinal", .integer).notNull()
                table.column("roleRaw", .text).notNull()
                table.column("content", .text).notNull()
                table.column("reasoning", .text)
                table.column("statusRaw", .text).notNull()
                table.column("errorMessage", .text)
                table.column("promptTokens", .integer)
                table.column("completionTokens", .integer)
                table.column("createdAt", .double).notNull()
            }

            try db.create(index: "idx_message_conv_ordinal",
                          on: "message",
                          columns: ["conversationId", "ordinal"])
        }

        migrator.registerMigration("v2_生成快照与恢复") { db in
            try db.alter(table: "message") { table in
                table.add(column: "generationID", .text)
                table.add(column: "snapshotSequence", .integer).notNull().defaults(to: 0)
                table.add(column: "checkpointAt", .double)
                table.add(column: "endReason", .text)
            }
        }

        return migrator
    }
}
