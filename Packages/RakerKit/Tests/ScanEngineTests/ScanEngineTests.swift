import Darwin
import FileSystemKit
import Foundation
import Testing
@testable import ScanEngine
@testable import SpaceIndex

@Suite("ScanEngine")
struct ScanEngineTests {
    @Test("Builds a tree whose folder totals add up")
    func folderTotals() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("a.bin", bytes: 120_000)
        try fixture.file("docs/b.pdf", bytes: 40_000)
        try fixture.file("docs/old/c.txt", bytes: 9_000)

        let report = try await ScanEngine().scan(ScanScope(path: fixture.path))
        let tree = report.tree

        #expect(report.completed)
        #expect(tree.rootPath == fixture.path)
        #expect(tree.descendantCount(of: tree.root) == 5)
        let files = (0 ..< tree.count).filter { tree.kind(of: $0) == .file }
        let fileTotal = files.reduce(UInt64(0)) { $0 + tree.allocatedSize(of: $1) }
        #expect(tree.allocatedSize(of: tree.root) == fileTotal)
        #expect(tree.size(of: tree.root).logical == 169_000)

        let docs = try #require(tree.index(ofPath: fixture.path + "/docs"))
        #expect(tree.size(of: docs).logical == 49_000)
        #expect(tree.path(of: docs) == fixture.path + "/docs")
        #expect(tree.name(of: docs) == "docs")
    }

    @Test("Counts hard-linked data once and never as reclaimable")
    func hardLinksCountedOnce() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("one.bin", bytes: 64_000)
        try fixture.hardLink("two.bin", to: "one.bin")

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree

        #expect(tree.size(of: tree.root).logical == 64_000)
        #expect(tree.size(of: tree.root).reclaimable == 0)
    }

    @Test("Lists the largest files first")
    func largestFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("small.bin", bytes: 10_000)
        try fixture.file("nested/huge.bin", bytes: 300_000)
        try fixture.file("medium.bin", bytes: 50_000)

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree
        let names = tree.largestFiles(limit: 2).map { tree.name(of: $0) }

        #expect(names == ["huge.bin", "medium.bin"])
        #expect(tree.largestChildren(of: tree.root).map { tree.name(of: $0) }.first == "nested")
    }

    @Test("Names locations it couldn't read")
    func skippedLocations() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("locked/x.bin", bytes: 1_000)
        chmod(fixture.path + "/locked", 0o000)

        let report = try await ScanEngine(homeDirectory: "/nonexistent").scan(ScanScope(path: fixture.path))

        let skipped = try #require(report.skipped.first)
        #expect(skipped.path == fixture.path + "/locked")
        #expect(skipped.reason == .permissionDenied(area: .rootOnly))
        let locked = try #require(report.tree.index(ofPath: fixture.path + "/locked"))
        #expect(report.tree.flags(of: locked).contains(.unreadable))
    }

    @Test("Rejects roots that are missing or not folders")
    func rootErrors() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("file.txt", bytes: 10)

        await #expect(throws: ScanError.rootNotFound(fixture.path + "/missing")) {
            try await ScanEngine().scan(ScanScope(path: fixture.path + "/missing"))
        }
        await #expect(throws: ScanError.rootNotDirectory(fixture.path + "/file.txt")) {
            try await ScanEngine().scan(ScanScope(path: fixture.path + "/file.txt"))
        }
    }

    @Test("Stops promptly when the task is cancelled")
    func cancellation() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for index in 0 ..< 200 {
            try fixture.file("d\(index)/f.bin", bytes: 10)
        }
        let task = Task { try await ScanEngine(workerCount: 1).scan(ScanScope(path: fixture.path)) }
        task.cancel()
        let report = try await task.value
        #expect(!report.completed || report.tree.count == 401)
    }

    @Test("Groups contents into recognizable kinds")
    func breakdown() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Installer.dmg", bytes: 50_000)
        try fixture.file("holiday.JPG", bytes: 30_000)
        try fixture.file("Example.app/Contents/MacOS/Example", bytes: 20_000)
        try fixture.file("project/node_modules/lib/index.js", bytes: 10_000)
        try fixture.file("notes.unknownext", bytes: 5_000)

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree
        let totals = StorageKindClassifier.breakdown(of: tree, under: tree.root)

        #expect((totals[.installers] ?? 0) >= 50_000)
        #expect((totals[.media] ?? 0) >= 30_000)
        #expect((totals[.apps] ?? 0) >= 20_000)
        #expect((totals[.developer] ?? 0) >= 10_000)
        #expect((totals[.other] ?? 0) >= 5_000)
        #expect(totals.values.reduce(0, +) == tree.allocatedSize(of: tree.root))
    }
}

/// A throwaway folder tree in the temporary directory.
struct Fixture {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        path = try FileStatus.resolvedPath(base.path)
    }

    func file(_ relative: String, bytes: Int) throws {
        let url = URL(fileURLWithPath: path + "/" + relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }

    func hardLink(_ relative: String, to existing: String) throws {
        guard link(path + "/" + existing, path + "/" + relative) == 0 else { throw POSIXError(.EIO) }
    }

    func remove() {
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let relative as String in enumerator {
                chmod(path + "/" + relative, 0o755)
            }
        }
        chmod(path + "/locked", 0o755)
        try? FileManager.default.removeItem(atPath: path)
    }
}
