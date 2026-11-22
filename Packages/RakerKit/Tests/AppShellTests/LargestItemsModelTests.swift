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
    @Test("A new scan starts afresh, without the old tree's selection")
    func rescan() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try write(300_000, to: folder + "/a.bin")
        try write(200_000, to: folder + "/b.bin")
        let model = try await scanned(folder)

        let old = try #require(model.report?.tree)
        let b = try #require(old.children(of: old.root).first { old.name(of: $0) == "b.bin" })
        model.selection = .largest
        model.largestSelection = [b]

        try write(400_000, to: folder + "/c.bin")
        model.startScan()
        try await waitUntil { model.phase == .finished }

        let tree = try #require(model.report?.tree)
        #expect(model.largestSelection.isEmpty)
        #expect(model.inspectedLocation == tree.root)
    }
}
