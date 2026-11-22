import Darwin
import FileSystemKit
import Foundation
import RakerModel
import ScanEngine
import Testing
@testable import DuplicateEngine

/// A throwaway folder tree with controllable contents.
private struct Fixture {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-dupes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        path = try FileStatus.resolvedPath(base.path)
    }

    /// Writes `bytes` bytes of a repeating pattern seeded by `seed`.
    @discardableResult
    func file(_ relative: String, bytes: Int, seed: UInt8 = 1, modified: Date? = nil) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let data = Data((0 ..< bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
        try data.write(to: URL(fileURLWithPath: full))
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: full)
        }
        return full
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

@Suite("DuplicateFinder")
struct DuplicateFinderTests {
    private func sets(in fixture: Fixture, minimumSize: UInt64 = 1_000) async throws -> [DuplicateSet] {
        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree
        return await DuplicateFinder(options: .init(minimumSize: minimumSize, homeDirectory: fixture.path)).find(in: tree)
    }

    @Test("Finds identical files in different folders and ignores look-alikes")
    func identicalFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Pictures/beach.jpg", bytes: 200_000, seed: 7)
        try fixture.file("Downloads/beach (1).jpg", bytes: 200_000, seed: 7)
        try fixture.file("Desktop/backup/beach.jpg", bytes: 200_000, seed: 7)
        try fixture.file("Documents/other.bin", bytes: 200_000, seed: 9)
        // Same size, same first and last 16 KB, different middle.
        var different = Data((0 ..< 200_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        different[100_000] ^= 0xFF
        try different.write(to: URL(fileURLWithPath: fixture.path + "/Documents/almost.jpg"))

        let found = try await sets(in: fixture)

        #expect(found.count == 1)
        let set = try #require(found.first)
        #expect(set.size == 200_000)
        #expect(set.files.map { ($0.path as NSString).lastPathComponent }.sorted() == ["beach (1).jpg", "beach.jpg", "beach.jpg"])
    }

    @Test("Hard links are one file, not duplicates")
    func hardLinks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.file("a/original.bin", bytes: 50_000)
        try FileManager.default.createDirectory(atPath: fixture.path + "/b", withIntermediateDirectories: true)
        #expect(link(original, fixture.path + "/b/link.bin") == 0)

        #expect(try await sets(in: fixture).isEmpty)
    }

    @Test("APFS clones are duplicates that free nothing")
    func clones() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.file("a/original.bin", bytes: 300_000)
        guard clonefile(original, fixture.path + "/a/clone.bin", 0) == 0 else { return }  // not APFS

        let set = try #require(try await sets(in: fixture).first)

        #expect(set.sharesAllData)
        #expect(set.reclaimable(keeping: original) == 0)
    }

    @Test("Skips small files, hidden folders, app bundles and ~/Library")
    func exclusions() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("small1.txt", bytes: 500)
        try fixture.file("small2.txt", bytes: 500)
        try fixture.file(".hidden/a.bin", bytes: 50_000)
        try fixture.file("Tool.app/Contents/a.bin", bytes: 50_000)
        try fixture.file("Library/Caches/a.bin", bytes: 50_000)
        try fixture.file("Documents/a.bin", bytes: 50_000)

        #expect(try await sets(in: fixture).isEmpty)
    }
}

@Suite("SurvivorStrategy")
struct SurvivorStrategyTests {
    private func file(_ path: String, modified: TimeInterval) -> DuplicateFile {
        DuplicateFile(path: path, identity: FileIdentity(device: 1, inode: 1, size: 1, modificationTime: 0),
                      modified: Date(timeIntervalSince1970: modified), reclaimable: 1)
    }

    @Test("Picks the copy that looks like the original")
    func original() {
        let set = DuplicateSet(id: "x", size: 1, allocatedPerCopy: 1, files: [
            file("/Users/alex/Downloads/report.pdf", modified: 1),
            file("/Users/alex/Documents/report copy.pdf", modified: 2),
            file("/Users/alex/Documents/report.pdf", modified: 3),
        ])
        #expect(SurvivorStrategy.original.keeper(in: set, home: "/Users/alex").path == "/Users/alex/Documents/report.pdf")
    }

    @Test("Oldest, newest, shortest path and locked originals")
    func otherStrategies() {
        let set = DuplicateSet(id: "x", size: 1, allocatedPerCopy: 1, files: [
            file("/a/long/path/photo.jpg", modified: 100),
            file("/b/photo.jpg", modified: 300),
            file("/c/photo (1).jpg", modified: 200),
        ])
        #expect(SurvivorStrategy.oldest.keeper(in: set).path == "/a/long/path/photo.jpg")
        #expect(SurvivorStrategy.newest.keeper(in: set).path == "/b/photo.jpg")
        #expect(SurvivorStrategy.shortestPath.keeper(in: set).path == "/b/photo.jpg")
        #expect(SurvivorStrategy.newest.keeper(in: set, locked: ["/c/photo (1).jpg"]).path == "/c/photo (1).jpg")
    }

    @Test("Recognizes copy-style names", arguments: [
        ("/x/report copy.pdf", true), ("/x/report copy 2.pdf", true), ("/x/report (1).pdf", true),
        ("/x/report 2.pdf", true), ("/x/report.pdf", false), ("/x/copyright.pdf", false), ("/x/2024 taxes.pdf", false),
    ])
    func copyNames(path: String, isCopy: Bool) {
        #expect(SurvivorStrategy.looksLikeCopy(path) == isCopy)
    }

    @Test("Findings never include the copy that stays")
    func findingsExcludeKeeper() {
        let set = DuplicateSet(id: "x", size: 10, allocatedPerCopy: 4_096, files: [
            file("/a/one.bin", modified: 1), file("/b/one.bin", modified: 2),
        ])
        let keeper = set.files[0]
        let findings = set.findings(removing: ["/a/one.bin", "/b/one.bin"], keeping: keeper)
        #expect(findings.count == 1)
        #expect(findings.first?.evidence == [.duplicateOf(path: "/a/one.bin", identity: keeper.identity)])
        #expect(findings.first?.safety == .review)
    }
}
