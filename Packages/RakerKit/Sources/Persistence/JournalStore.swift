import Foundation
import GRDB
import RakerModel

/// The history of cleanups: what was removed, where it went, and what was put back.
public final class JournalStore: Sendable {
    private let writer: any DatabaseWriter

    /// Opens a store on any GRDB writer and brings its schema up to date.
    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The store in Raker's Application Support folder, created if needed.
    public static func open(at url: URL = AppPaths.database) throws -> JournalStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.label = "Raker journal"
        return try JournalStore(writer: DatabasePool(path: url.path, configuration: configuration))
    }

    /// A store that lives in memory, for tests and previews.
    public static func inMemory() throws -> JournalStore {
        try JournalStore(writer: DatabaseQueue())
    }

    public func save(_ receipt: CleanupReceipt) throws {
        try writer.write { db in
            try CleanupRow(receipt).insert(db)
            for (position, item) in receipt.items.enumerated() {
                try CleanupItemRow(item, cleanupID: receipt.id, position: position).insert(db)
            }
        }
    }

    /// Recent receipts, newest first.
    public func receipts(limit: Int = 50) throws -> [CleanupReceipt] {
        try writer.read { db in
            let cleanups = try CleanupRow.order(Column("startedAt").desc).limit(limit).fetchAll(db)
            return try cleanups.map { try Self.receipt(for: $0, in: db) }
        }
    }

    public func receipt(id: UUID) throws -> CleanupReceipt? {
        try writer.read { db in
            try CleanupRow.fetchOne(db, key: id.uuidString).map { try Self.receipt(for: $0, in: db) }
        }
    }

    /// Records that an item was put back from the Trash.
    public func markRestored(itemID: UUID, at date: Date) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE cleanupItem SET restoredAt = ? WHERE id = ?",
                arguments: [date, itemID.uuidString]
            )
        }
    }

    private static func receipt(for cleanup: CleanupRow, in db: Database) throws -> CleanupReceipt {
        let items = try CleanupItemRow
            .filter(Column("cleanupId") == cleanup.id.uuidString)
            .order(Column("position"))
            .fetchAll(db)
        return CleanupReceipt(
            id: cleanup.id,
            startedAt: cleanup.startedAt,
            finishedAt: cleanup.finishedAt,
            items: items.map(\.item),
            spaceBefore: cleanup.spaceBefore,
            spaceAfter: cleanup.spaceAfter
        )
    }

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
        return migrator
    }
}

// MARK: - Rows

/// IDs are stored as text and nested values (sizes, destinations, outcomes) as JSON, so the
/// database stays readable with any SQLite tool.
private struct CleanupRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cleanup"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var spaceBefore: VolumeSpace?
    var spaceAfter: VolumeSpace?

    init(_ receipt: CleanupReceipt) {
        id = receipt.id
        startedAt = receipt.startedAt
        finishedAt = receipt.finishedAt
        spaceBefore = receipt.spaceBefore
        spaceAfter = receipt.spaceAfter
    }
}

private struct CleanupItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "cleanupItem"
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    var id: UUID
    var cleanupId: UUID
    var position: Int
    var findingId: String
    var path: String
    var destination: Destination
    var size: SizeEstimate
    var outcome: ItemOutcome
    var restoredAt: Date?

    init(_ item: ExecutedItem, cleanupID: UUID, position: Int) {
        id = item.id
        cleanupId = cleanupID
        self.position = position
        findingId = item.findingID
        path = item.path
        destination = item.destination
        size = item.size
        outcome = item.outcome
        restoredAt = item.restoredAt
    }

    var item: ExecutedItem {
        ExecutedItem(id: id, findingID: findingId, path: path, destination: destination, size: size,
                     outcome: outcome, restoredAt: restoredAt)
    }
}
