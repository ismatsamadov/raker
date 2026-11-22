import FileSystemKit
import Foundation
import Persistence
import Testing
@testable import AppShell

private struct TimedOut: Error {}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(30)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw TimedOut() }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// An empty folder of its own, under the temporary directory.
private func makeFolder() throws -> String {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-largest-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return try FileStatus.resolvedPath(base.path)
}

private func write(_ count: Int, to path: String) throws {
    try Data(repeating: 0x42, count: count).write(to: URL(fileURLWithPath: path))
}

/// A model whose history, rules and Tray live in memory, after scanning `folder`.
@MainActor
private func scanned(_ folder: String) async throws -> AppModel {
    let model = AppModel(database: try AppDatabase.inMemory())
    model.scope = .folder(URL(fileURLWithPath: folder))
    model.startScan()
    try await waitUntil { model.phase == .finished }
    return model
}

@Suite("Largest Items in the app model")
@MainActor
struct LargestItemsModelTests {
    @Test("A new scan starts afresh, without the old tree's selection, hover or Space Lens")
    func rescan() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write(300_000, to: folder + "/a.bin")
        try write(200_000, to: folder + "/b.bin")
        let model = try await scanned(folder)

        let old = try #require(model.report?.tree)
        let b = try #require(old.children(of: old.root).first { old.name(of: $0) == "b.bin" })
        model.selection = .largest
        model.largestMode = .lens
        model.largestSelection = [b]
        model.lensHovered = .item(b)
        #expect(model.lensSegments.count == 2)

        try write(400_000, to: folder + "/c.bin")
        model.startScan()
        // Space Lens stays on screen while the new scan runs, still showing the old tree.
        #expect(model.lensSegments.count == 2)
        try await waitUntil { model.phase == .finished }

        let tree = try #require(model.report?.tree)
        #expect(model.largestSelection.isEmpty)
        #expect(model.inspectedLocation == tree.root)
        #expect(model.lensHovered == nil)
        let names = model.lensSegments.compactMap { segment -> String? in
            guard case .item(let index) = segment.key else { return nil }
            return tree.name(of: index)
        }
        #expect(names.sorted() == ["a.bin", "b.bin", "c.bin"])
    }

    @Test("Space Lens fills each ring, however many items a folder holds")
    func crowdedFolder() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write(1_000_000, to: folder + "/big.bin")
        for number in 0 ..< 2_100 {
            try write(5_000, to: folder + "/small-\(number).bin")
        }
        let model = try await scanned(folder)

        let tree = try #require(model.report?.tree)
        let big = try #require(tree.children(of: tree.root).first { tree.name(of: $0) == "big.bin" })
        let ring = model.lensSegments.filter { $0.depth == 1 }
        #expect(ring.map(\.key) == [.item(big), .smaller(parent: tree.root)])
        #expect(abs((ring.last?.end ?? 0) - 1) < 1e-9)
    }
}
