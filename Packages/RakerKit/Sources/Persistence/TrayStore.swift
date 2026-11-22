import Foundation
import GRDB
import RakerModel

/// What's in the Tray, kept so it survives relaunches.
public struct TrayStore: Sendable {
    let writer: any DatabaseWriter

    /// The staged items, in staging order. Items this version can't read are left out.
    public func all() throws -> [TrayItem] {
        try writer.read { db in
            try TrayItemRow.order(Column("position")).fetchAll(db).compactMap(\.item)
        }
    }

    /// Replaces what's stored with `items`.
    public func save(_ items: [TrayItem]) throws {
        let rows = try items.enumerated().map { try TrayItemRow($0.element, position: $0.offset) }
        try writer.write { db in
            try TrayItemRow.deleteAll(db)
            for row in rows {
                try row.insert(db)
            }
        }
    }
}

private struct TrayItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "trayItem"

    var findingId: String
    var position: Int
    var source: String
    /// The finding as JSON, decoded on its own so one unreadable item doesn't hide the rest.
    var finding: String
    var stagedAt: Date

    init(_ item: TrayItem, position: Int) throws {
        findingId = item.id
        self.position = position
        source = item.source.rawValue
        finding = String(decoding: try JSONEncoder().encode(item.finding), as: UTF8.self)
        stagedAt = item.stagedAt
    }

    var item: TrayItem? {
        guard let source = TrayItem.Source(rawValue: source),
              let finding = try? JSONDecoder().decode(Finding.self, from: Data(finding.utf8))
        else { return nil }
        return TrayItem(finding: finding, source: source, stagedAt: stagedAt)
    }
}
