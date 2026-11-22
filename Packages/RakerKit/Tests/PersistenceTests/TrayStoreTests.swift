import Foundation
import GRDB
import RakerModel
import Testing
@testable import Persistence

private func item(_ name: String, source: TrayItem.Source, stagedAt seconds: TimeInterval) -> TrayItem {
    let identity = FileIdentity(device: 1, inode: 42, size: 10, modificationTime: 0)
    let finding = Finding(
        id: "\(source.rawValue):/Users/alex/\(name)", subject: .file(FileRef(path: "/Users/alex/\(name)", identity: identity)),
        category: "test", safety: .review, size: SizeEstimate(logical: 10, allocated: 16, reclaimable: 16),
        evidence: [.lastOpened(Date(timeIntervalSince1970: 1_000))], explanation: "A test item."
    )
    return TrayItem(finding: finding, source: source, stagedAt: Date(timeIntervalSince1970: seconds))
}

@Suite("TrayStore")
struct TrayStoreTests {
    @Test("Saves and restores the Tray in staging order")
    func roundTrip() throws {
        let store = try AppDatabase.inMemory().tray
        let items = [
            item("b.dmg", source: .downloads, stagedAt: 20),
            item("a.mov", source: .largeAndOld, stagedAt: 10),
            item("c.zip", source: .duplicates, stagedAt: 30),
        ]
        try store.save(items)
        #expect(try store.all() == items)

        try store.save(Array(items.dropFirst()))
        #expect(try store.all().map(\.id) == items.dropFirst().map(\.id))

        try store.save([])
        #expect(try store.all().isEmpty)
    }

    @Test("Leaves out items this version can't read, keeping the rest")
    func unreadableItems() throws {
        let database = try AppDatabase.inMemory()
        try database.tray.save([item("a.dmg", source: .downloads, stagedAt: 10)])
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO trayItem (findingId, position, source, finding, stagedAt)
                VALUES ('future:1', 1, 'somethingNew', '{}', '2026-01-01 00:00:00.000'),
                       ('broken:1', 2, 'downloads', '{"not": "a finding"}', '2026-01-01 00:00:00.000')
                """)
        }
        #expect(try database.tray.all().map(\.id) == ["downloads:/Users/alex/a.dmg"])
    }

    @Test("Upgrades a database created before the Tray existed")
    func upgrade() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raker-tray-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("raker.sqlite")
        let old = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(old, upTo: "v2: user rules")
        try UserRuleStore(writer: old).add(UserRule(path: "/Users/alex/Projects", kind: .exclude))
        try old.close()

        let upgraded = try AppDatabase.open(at: url)

        #expect(try upgraded.userRules.all().count == 1)
        try upgraded.tray.save([item("a.dmg", source: .downloads, stagedAt: 10)])
        #expect(try upgraded.tray.all().count == 1)
    }
}
