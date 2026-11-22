import Foundation
import GRDB
import RakerModel
import Testing
@testable import Persistence

@Suite("UserRuleStore")
struct UserRuleStoreTests {
    @Test("Adds, lists and removes rules; the same rule isn't added twice")
    func addListRemove() throws {
        let store = try AppDatabase.inMemory().userRules
        let exclude = UserRule(path: "/Users/alex/Projects", kind: .exclude, createdAt: Date(timeIntervalSince1970: 1))
        let lock = UserRule(path: "/Users/alex/Pictures/Originals", kind: .lockOriginal, createdAt: Date(timeIntervalSince1970: 2))
        try store.add(exclude)
        try store.add(lock)
        try store.add(UserRule(path: "/Users/alex/Projects", kind: .exclude))

        let rules = try store.all()
        #expect(rules.map(\.id) == [exclude.id, lock.id])
        #expect(rules.exclusions == ["/Users/alex/Projects"])
        #expect(rules.lockedOriginals == ["/Users/alex/Pictures/Originals"])

        try store.remove(id: exclude.id)
        #expect(try store.all().map(\.id) == [lock.id])
    }

    @Test("Upgrades a database created before rules existed, keeping its history")
    func upgradesExistingDatabase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raker-upgrade-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("raker.sqlite")

        // A database as the first version left it.
        let old = try DatabaseQueue(path: url.path)
        try AppDatabase.migrator.migrate(old, upTo: "v1: cleanup history")
        let receipt = CleanupReceipt(id: UUID(), startedAt: Date(), finishedAt: Date(), items: [], spaceBefore: nil, spaceAfter: nil)
        try JournalStore(writer: old).save(receipt)
        try old.close()

        let upgraded = try AppDatabase.open(at: url)

        #expect(try upgraded.journal.receipt(id: receipt.id) != nil)
        try upgraded.userRules.add(UserRule(path: "/tmp/x", kind: .exclude))
        #expect(try upgraded.userRules.all().count == 1)
    }
}
