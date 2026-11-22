import Darwin
import Foundation
import Synchronization
import Testing
@testable import FileSystemKit

/// Records everything the walker reports, keyed by absolute path.
final class RecordingSink: WalkSink {
    struct Record: Sendable {
        var kind: EntryKind
        var logical: UInt64
        var allocated: UInt64
        var privateSize: UInt64
        var flags: EntryFlags
        var linkCount: UInt32
    }

    private struct State {
        var records: [String: Record] = [:]
        var failures: [String: Int32] = [:]
    }

    private let state = Mutex(State())
    private let nextToken = Atomic<UInt32>(1)

    func begin(rootPath: String) -> UInt32 { 0 }

    func directoryRead(token: UInt32, path: String, batch: EntryBatch, descend: [Int]) -> [UInt32] {
        state.withLock { state in
            for index in 0 ..< batch.count {
                state.records[path + "/" + batch.name(at: index)] = Record(
                    kind: batch.kinds[index],
                    logical: batch.logicalSizes[index],
                    allocated: batch.allocatedSizes[index],
                    privateSize: batch.privateSizes[index],
                    flags: batch.flags[index],
                    linkCount: batch.linkCounts[index]
                )
            }
        }
        return descend.map { _ in nextToken.wrappingAdd(1, ordering: .relaxed).oldValue }
    }

    func directoryFailed(token: UInt32, path: String, error: Int32) {
        state.withLock { $0.failures[path] = error }
    }

    var records: [String: Record] { state.withLock { $0.records } }
    var failures: [String: Int32] { state.withLock { $0.failures } }
}

@Suite("BulkWalker")
struct BulkWalkerTests {
    @Test("Reads every entry with its kind and sizes")
    func readsEntries() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("a.bin", bytes: 100_000)
        try fixture.file("sub/b.bin", bytes: 50_000)
        try fixture.file("sub/deeper/c.bin", bytes: 10_000)
        try fixture.file(".hidden", bytes: 10)

        let sink = RecordingSink()
        #expect(BulkWalker().walk(rootPath: fixture.path, sink: sink))

        let records = sink.records
        #expect(records.count == 6)
        let a = try #require(records[fixture.absolute("a.bin")])
        #expect(a.kind == .file)
        #expect(a.logical == 100_000)
        #expect(a.allocated >= 100_000)
        #expect(records[fixture.absolute("sub")]?.kind == .directory)
        #expect(records[fixture.absolute("sub/deeper/c.bin")]?.logical == 10_000)
        #expect(records[fixture.absolute(".hidden")]?.flags.contains(.hidden) == true)
        #expect(sink.failures.isEmpty)
    }

    @Test("Never follows symlinks")
    func symlinksAreNotFollowed() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.directory("real")
        try fixture.file("real/inside.bin", bytes: 1_000)
        try fixture.symlink("link-to-system", to: "/System")
        try fixture.symlink("link-to-real", to: fixture.absolute("real"))

        let sink = RecordingSink()
        BulkWalker().walk(rootPath: fixture.path, sink: sink)

        let records = sink.records
        #expect(records[fixture.absolute("link-to-system")]?.kind == .symlink)
        #expect(records[fixture.absolute("link-to-real")]?.kind == .symlink)
        #expect(!records.keys.contains { $0.hasPrefix(fixture.absolute("link-to-system") + "/") })
        #expect(!records.keys.contains { $0.hasPrefix(fixture.absolute("link-to-real") + "/") })
    }

    @Test("Reports folders it can't read and keeps going")
    func unreadableFolders() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("locked/secret.bin", bytes: 1_000)
        try fixture.file("open/visible.bin", bytes: 1_000)
        fixture.setPermissions("locked", 0o000)

        let sink = RecordingSink()
        BulkWalker().walk(rootPath: fixture.path, sink: sink)

        #expect(sink.failures[fixture.absolute("locked")] == EACCES)
        #expect(sink.records[fixture.absolute("open/visible.bin")] != nil)
        #expect(sink.records[fixture.absolute("locked/secret.bin")] == nil)
    }

    @Test("Flags hard links")
    func hardLinks() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("original.bin", bytes: 40_000)
        try fixture.hardLink("sub-link.bin", to: "original.bin")

        let sink = RecordingSink()
        BulkWalker().walk(rootPath: fixture.path, sink: sink)

        let original = try #require(sink.records[fixture.absolute("original.bin")])
        #expect(original.linkCount == 2)
        #expect(original.flags.contains(.multiplyLinked))
    }

    @Test("Reports APFS private size, which excludes blocks shared with clones")
    func clonesShareBlocks() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("solo.bin", bytes: 300_000)
        try fixture.file("original.bin", bytes: 300_000)
        guard fixture.clone("clone.bin", from: "original.bin") else { return }  // not APFS

        let sink = RecordingSink()
        BulkWalker().walk(rootPath: fixture.path, sink: sink)

        let solo = try #require(sink.records[fixture.absolute("solo.bin")])
        let clone = try #require(sink.records[fixture.absolute("clone.bin")])
        try #require(solo.flags.contains(.privateSizeKnown))
        #expect(solo.privateSize > 0)
        #expect(solo.privateSize <= solo.allocated)
        #expect(clone.privateSize < clone.allocated)
    }

    @Test("Stops when cancelled")
    func cancellation() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        for index in 0 ..< 20 {
            try fixture.file("d\(index)/f.bin", bytes: 10)
        }
        let cancellation = CancellationFlag()
        cancellation.cancel()

        let sink = RecordingSink()
        let completed = BulkWalker().walk(rootPath: fixture.path, sink: sink, cancellation: cancellation)

        #expect(!completed)
        #expect(sink.records.isEmpty)
    }

    @Test("Opens paths longer than PATH_MAX")
    func longPaths() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        let components = Array(repeating: String(repeating: "n", count: 200), count: 6)
        try fixture.deepDirectories(components)
        let deep = fixture.absolute(components.joined(separator: "/"))
        #expect(deep.utf8.count > Int(PATH_MAX))

        let fd = BulkWalker.openDirectory(deep)
        #expect(fd >= 0)
        if fd >= 0 { close(fd) }
    }
}
