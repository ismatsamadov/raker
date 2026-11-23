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

/// A folder of its own under the temporary directory, with the same 200 KB in each named file.
private func makeFolder(_ names: String...) throws -> String {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-scan-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let folder = try FileStatus.resolvedPath(base.path)
    for name in names {
        try Data(repeating: 0x42, count: 200_000).write(to: URL(fileURLWithPath: folder + "/" + name))
    }
    return folder
}

@Suite("Scan state in the app model")
@MainActor
struct ScanStateTests {
    @Test("Stopping a scan goes back to the last complete scan and its folder")
    func stopKeepsLastScan() async throws {
        let first = try makeFolder("a.bin")
        let second = try makeFolder("b.bin")
        defer {
            try? FileManager.default.removeItem(atPath: first)
            try? FileManager.default.removeItem(atPath: second)
        }
        let model = AppModel(database: try AppDatabase.inMemory())
        let scanned = ScanScopeChoice.folder(URL(fileURLWithPath: first))
        model.scope = scanned
        model.startScan()
        try await waitUntil { model.phase == .finished }

        // Stopped before it reads anything, the second scan leaves the first one in place.
        model.scope = .folder(URL(fileURLWithPath: second))
        model.startScan()
        model.cancelScan()
        try await waitUntil { model.phase != .scanning }

        #expect(model.phase == .finished)
        #expect(model.scope == scanned)
        #expect(model.report?.completed == true)
        #expect(model.report?.tree.rootPath == first)
    }

    @Test("Stopping the first scan leaves nothing half-read on screen")
    func stopFirstScan() async throws {
        let folder = try makeFolder("a.bin")
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let model = AppModel(database: try AppDatabase.inMemory())
        model.scope = .folder(URL(fileURLWithPath: folder))
        model.startScan()
        model.cancelScan()
        try await waitUntil { model.phase != .scanning }

        #expect(model.phase == .idle)
        #expect(model.report == nil)
    }
}
