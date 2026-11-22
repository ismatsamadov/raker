import Foundation
import GRDB

/// Raker's database: cleanup history, the user's rules and the Tray, in one SQLite file.
public final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    /// Opens a database on any GRDB writer and brings its schema up to date.
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The database in Raker's Application Support folder, created if needed.
    public static func open(at url: URL = AppPaths.database) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.label = "Raker"
        return try AppDatabase(writer: DatabasePool(path: url.path, configuration: configuration))
    }

    /// A database that lives in memory, for tests and previews.
    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    public var journal: JournalStore { JournalStore(writer: writer) }
    public var userRules: UserRuleStore { UserRuleStore(writer: writer) }
    public var tray: TrayStore { TrayStore(writer: writer) }

    /// Schema changes, in order. Never edit a registered migration; add a new one.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1: cleanup history") { db in
            try db.create(table: "cleanup") { table in
                table.primaryKey("id", .text)
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime).notNull()
                table.column("spaceBefore", .jsonText)
                table.column("spaceAfter", .jsonText)
            }
            try db.create(table: "cleanupItem") { table in
                table.primaryKey("id", .text)
                table.belongsTo("cleanup", onDelete: .cascade).notNull()
                table.column("position", .integer).notNull()
                table.column("findingId", .text).notNull()
                table.column("path", .text).notNull()
                table.column("destination", .jsonText).notNull()
                table.column("size", .jsonText).notNull()
                table.column("outcome", .jsonText).notNull()
                table.column("restoredAt", .datetime)
            }
        }
        migrator.registerMigration("v2: user rules") { db in
            try db.create(table: "userRule") { table in
                table.primaryKey("id", .text)
                table.column("path", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("createdAt", .datetime).notNull()
                table.uniqueKey(["path", "kind"])
            }
        }
        migrator.registerMigration("v3: tray") { db in
            try db.create(table: "trayItem") { table in
                table.primaryKey("findingId", .text)
                table.column("position", .integer).notNull()
                table.column("source", .text).notNull()
                table.column("finding", .jsonText).notNull()
                table.column("stagedAt", .datetime).notNull()
            }
        }
        return migrator
    }
}
