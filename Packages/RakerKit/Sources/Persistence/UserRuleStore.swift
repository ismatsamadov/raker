import Foundation
import GRDB
import RakerModel

/// The user's exclusions and locked originals.
public struct UserRuleStore: Sendable {
    let writer: any DatabaseWriter

    /// Every rule, oldest first.
    public func all() throws -> [UserRule] {
        try writer.read { db in
            try UserRuleRow.order(Column("createdAt")).fetchAll(db).compactMap(\.rule)
        }
    }

    /// Adds a rule; a rule of the same kind for the same path is kept as it is.
    public func add(_ rule: UserRule) throws {
        try writer.write { db in
            try UserRuleRow(rule).insert(db, onConflict: .ignore)
        }
    }

    public func remove(id: UUID) throws {
        try writer.write { db in
            _ = try UserRuleRow.deleteOne(db, key: id.uuidString)
        }
    }
}

private struct UserRuleRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "userRule"

    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .uppercaseString
    }

    var id: UUID
    var path: String
    var kind: String
    var createdAt: Date

    init(_ rule: UserRule) {
        id = rule.id
        path = rule.path
        kind = rule.kind.rawValue
        createdAt = rule.createdAt
    }

    /// Nil for a kind this version doesn't know, so newer databases still open.
    var rule: UserRule? {
        UserRule.Kind(rawValue: kind).map { UserRule(id: id, path: path, kind: $0, createdAt: createdAt) }
    }
}
