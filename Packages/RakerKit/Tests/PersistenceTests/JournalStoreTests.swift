import Foundation
import RakerModel
import Testing
@testable import Persistence

private func sampleReceipt(startedAt: Date, trashPath: String = "/Users/alex/.Trash/cache") -> CleanupReceipt {
    let size = SizeEstimate(logical: 1_000, allocated: 4_096, reclaimable: 4_096)
    return CleanupReceipt(
        id: UUID(),
        startedAt: startedAt,
        finishedAt: startedAt.addingTimeInterval(2),
        items: [
            ExecutedItem(findingID: "a", path: "/Users/alex/Library/Caches/a", destination: .delete, size: size, outcome: .deleted),
            ExecutedItem(findingID: "b", path: "/Users/alex/Library/Caches/b", destination: .trash, size: size,
                         outcome: .movedToTrash(trashPath: trashPath)),
            ExecutedItem(findingID: "c", path: "/Users/alex/Library/Caches/c", destination: .delete, size: size,
                         outcome: .skipped(.appRunning(bundleID: "com.example.App"))),
        ],
        spaceBefore: VolumeSpace(total: 1_000_000, free: 500_000, availableIncludingPurgeable: 600_000),
        spaceAfter: VolumeSpace(total: 1_000_000, free: 504_096, availableIncludingPurgeable: 604_096)
    )
}

@Suite("JournalStore")
struct JournalStoreTests {
    @Test("Saves and reads back a receipt with every outcome")
    func roundTrip() throws {
        let store = try JournalStore.inMemory()
        let receipt = sampleReceipt(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try store.save(receipt)

        let loaded = try #require(try store.receipt(id: receipt.id))
        #expect(loaded.items == receipt.items)
        #expect(loaded.spaceBefore == receipt.spaceBefore)
        #expect(loaded.observedChange == 4_096)
        #expect(loaded.deleted.count == 1)
        #expect(loaded.movedToTrash.count == 1)
        #expect(loaded.skipped.count == 1)
    }

    @Test("Lists receipts newest first")
    func ordering() throws {
        let store = try JournalStore.inMemory()
        let older = sampleReceipt(startedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let newer = sampleReceipt(startedAt: Date(timeIntervalSince1970: 1_800_100_000))
        try store.save(older)
        try store.save(newer)

        #expect(try store.receipts().map(\.id) == [newer.id, older.id])
        #expect(try store.receipts(limit: 1).map(\.id) == [newer.id])
    }

    @Test("Records restored items")
    func markRestored() throws {
        let store = try JournalStore.inMemory()
        let receipt = sampleReceipt(startedAt: Date())
        try store.save(receipt)
        let trashed = try #require(receipt.items.first { $0.isRestorable })

        try store.markRestored(itemID: trashed.id, at: Date())

        let loaded = try #require(try store.receipt(id: receipt.id))
        #expect(loaded.items.first { $0.id == trashed.id }?.restoredAt != nil)
        #expect(loaded.items.filter(\.isRestorable).isEmpty)
    }

    @Test("Persists to a file and survives reopening")
    func fileBacked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("raker-journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("raker.sqlite")
        let receipt = sampleReceipt(startedAt: Date())

        try JournalStore.open(at: url).save(receipt)
        let reopened = try JournalStore.open(at: url)

        #expect(try reopened.receipt(id: receipt.id)?.items.count == 3)
    }
}
