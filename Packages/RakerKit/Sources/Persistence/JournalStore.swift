import Foundation
import GRDB
import RakerModel

/// The history of cleanups: what was removed, where it went, and what was put back.
public struct JournalStore: Sendable {
    let writer: any DatabaseWriter

    /// The journal in Raker's database, created if needed.
    public static func open(at url: URL = AppPaths.database) throws -> JournalStore {
        try AppDatabase.open(at: url).journal
    }

    /// A journal that lives in memory, for tests and previews.
    public static func inMemory() throws -> JournalStore {
        try AppDatabase.inMemory().journal
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
