import Foundation
import RakerModel
import Testing

private func finding(_ name: String, allocated: UInt64, reclaimable: UInt64? = nil) -> Finding {
    let identity = FileIdentity(device: 1, inode: UInt64(name.hashValue.magnitude), size: allocated, modificationTime: 0)
    return Finding(
        id: "test:/tmp/\(name)", subject: .file(FileRef(path: "/tmp/\(name)", identity: identity)), category: "test",
        safety: .review, size: SizeEstimate(logical: allocated, allocated: allocated, reclaimable: reclaimable),
        explanation: "A test item."
    )
}

@Suite("Tray")
struct TrayTests {
    @Test("Keeps items in staging order, each finding once")
    func staging() {
        var tray = Tray()
        tray.stage(TrayItem(finding: finding("a", allocated: 100), source: .downloads))
        tray.stage(TrayItem(finding: finding("b", allocated: 200), source: .cleanup))
        tray.stage(TrayItem(finding: finding("a", allocated: 150), source: .downloads))

        #expect(tray.items.map(\.id) == ["test:/tmp/a", "test:/tmp/b"])
        #expect(tray.items.first?.finding.size.allocated == 150)
        #expect(tray.contains("test:/tmp/b"))
        #expect(tray.ids(from: .downloads) == ["test:/tmp/a"])
        #expect(tray.items(from: .cleanup).map(\.id) == ["test:/tmp/b"])

        // Staged again from another section, it moves there and keeps its place.
        tray.stage(TrayItem(finding: finding("a", allocated: 150), source: .largeAndOld))
        #expect(tray.items.map(\.id) == ["test:/tmp/a", "test:/tmp/b"])
        #expect(tray.ids(from: .downloads).isEmpty)
        #expect(tray.ids(from: .largeAndOld) == ["test:/tmp/a"])
    }

    @Test("Takes items out one at a time, by condition, or all at once")
    func unstaging() {
        var tray = Tray(items: ["a", "b", "c"].map { TrayItem(finding: finding($0, allocated: 10), source: .largeAndOld) })
        tray.unstage("test:/tmp/b")
        #expect(tray.items.map(\.id) == ["test:/tmp/a", "test:/tmp/c"])
        #expect(!tray.contains("test:/tmp/b"))

        tray.unstage { $0.id.hasSuffix("/c") }
        #expect(tray.items.map(\.id) == ["test:/tmp/a"])
        #expect(!tray.contains("test:/tmp/c"))
        #expect(tray.ids(from: .largeAndOld) == ["test:/tmp/a"])

        tray.removeAll()
        #expect(tray.isEmpty)
        #expect(!tray.contains("test:/tmp/a"))
    }

    @Test("Adds up what the staged items take and what removing them frees")
    func totals() {
        let tray = Tray(items: [
            TrayItem(finding: finding("a", allocated: 1_000, reclaimable: 400), source: .duplicates),
            TrayItem(finding: finding("b", allocated: 2_000, reclaimable: 2_000), source: .downloads),
            TrayItem(finding: finding("c", allocated: 500, reclaimable: nil), source: .cleanup),
        ])
        #expect(tray.count == 3)
        #expect(tray.allocatedBytes == 3_500)
        // Unknown counts as nothing freed: the total is a lower bound.
        #expect(tray.reclaimableBytes == 2_400)
    }

    @Test("Items survive encoding, as the database stores them")
    func codable() throws {
        let item = TrayItem(finding: finding("a", allocated: 10), source: .duplicates, stagedAt: Date(timeIntervalSince1970: 5))
        let decoded = try JSONDecoder().decode(TrayItem.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}
