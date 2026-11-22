import FileSystemKit
import Foundation
import Persistence
import RakerModel
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

/// A folder with three identical files and one unique one, scanned and compared by a model
/// whose history, rules and Tray live in memory.
@MainActor
private struct Comparison {
    let folder: String
    let database: AppDatabase
    let model: AppModel

    init() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-tray-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        folder = try FileStatus.resolvedPath(base.path)
        let copy = Data(repeating: 0x42, count: 200_000)
        for name in ["a.bin", "b.bin", "c.bin"] {
            try copy.write(to: URL(fileURLWithPath: folder + "/" + name))
        }
        try Data(repeating: 0x17, count: 200_000).write(to: URL(fileURLWithPath: folder + "/unique.bin"))
        database = try AppDatabase.inMemory()
        model = AppModel(database: database)
        model.scope = .folder(URL(fileURLWithPath: folder))
        model.startScan()
        try await waitUntil { model.phase == .finished }
        model.findDuplicates()
        try await waitUntil { model.duplicatesPhase == .finished }
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: folder)
    }
}

@Suite("Tray in the app model", .serialized)
@MainActor
struct TrayModelTests {
    @Test("Staged copies always name the copy that stays, even when it changes")
    func duplicatesFollowTheKeeper() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        let model = comparison.model
        let set = try #require(model.duplicateSets.first)
        #expect(set.files.count == 3)

        model.selectAllDuplicates()
        let keeper = model.keeper(of: set)
        #expect(model.tray.count == 2)
        #expect(!model.duplicatesSelection.contains(keeper.path))
        #expect(model.tray.items.allSatisfy {
            $0.source == .duplicates && $0.finding.evidence == [.duplicateOf(path: keeper.path, identity: keeper.identity)]
        })

        // Keeping a staged copy instead takes it out, and the other copy now names it.
        let chosen = try #require(set.files.first { $0.path != keeper.path })
        let third = try #require(set.files.first { $0.path != keeper.path && $0.path != chosen.path })
        model.keep(chosen, in: set)
        #expect(model.duplicatesSelection == [third.path])
        #expect(model.tray.items.first?.finding.evidence == [.duplicateOf(path: chosen.path, identity: chosen.identity)])
    }

    @Test("Locking a staged copy makes it the one that stays; excluding one takes it out")
    func userRules() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        let model = comparison.model
        let set = try #require(model.duplicateSets.first)
        model.selectAllDuplicates()
        let staged = model.duplicatesSelection.sorted()
        #expect(staged.count == 2)

        model.addUserRule(.lockOriginal, for: staged[0])
        let locked = try #require(set.files.first { $0.path == staged[0] })
        #expect(model.keeper(of: set).path == locked.path)
        #expect(model.duplicatesSelection == [staged[1]])
        #expect(model.tray.items.first?.finding.evidence == [.duplicateOf(path: locked.path, identity: locked.identity)])

        model.addUserRule(.exclude, for: staged[1])
        #expect(model.tray.isEmpty)
    }

    @Test("The Tray survives a relaunch, without items that disappeared meanwhile")
    func relaunch() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        comparison.model.selectAllDuplicates()
        let staged = comparison.model.duplicatesSelection.sorted()
        #expect(staged.count == 2)
        try FileManager.default.removeItem(atPath: staged[0])

        let relaunched = AppModel(database: comparison.database)
        #expect(relaunched.tray.count == 2)
        try await waitUntil { relaunched.tray.count == 1 }
        #expect(relaunched.tray.items.map(\.finding.path) == [staged[1]])
    }

    @Test("Anything found while exploring can be staged, unless the policy refuses it")
    func explorerStaging() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        let model = comparison.model
        let tree = try #require(model.report?.tree)
        let unique = try #require(tree.largestChildren(of: tree.root, limit: 10).first { tree.name(of: $0) == "unique.bin" })
        model.selection = .largest
        model.largestSelection = [unique]

        let finding = try #require(model.inspectedFinding)
        #expect(finding.id == "largest:\(comparison.folder)/unique.bin")
        #expect(model.locationExplanation?.path == finding.path)
        // A person's own choice: it goes to the Trash, and isn't presented as a rule's finding.
        #expect(finding.safety == .review)
        #expect(!finding.evidence.contains { if case .rule = $0 { true } else { false } })
        model.toggleStaged(finding)
        #expect(model.tray.items.map(\.source) == [.largest])
        model.toggleStaged(finding)
        #expect(model.tray.isEmpty)

        model.addUserRule(.exclude, for: finding.path)
        #expect(!model.canStageFromExplorer(finding))
        model.toggleStaged(finding)
        #expect(model.tray.isEmpty)
    }

    @Test("Several rows of Largest Items can be staged at once")
    func explorerBulk() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        let model = comparison.model
        let tree = try #require(model.report?.tree)
        let rows = Set(tree.largestChildren(of: tree.root, limit: 10))
        model.selection = .largest

        model.setStaged(rows, true)
        #expect(model.tray.count == 4)
        #expect(model.tray.items.allSatisfy { $0.source == .largest })
        model.setStaged(rows, false)
        #expect(model.tray.isEmpty)
    }

    @Test("Clearing and unstaging take items out of the Tray only")
    func clearing() async throws {
        let comparison = try await Comparison()
        defer { comparison.remove() }
        let model = comparison.model
        model.selectAllDuplicates()
        let first = try #require(model.tray.items.first)

        model.unstage(first.id)
        #expect(model.tray.count == 1)
        model.clearTray()
        #expect(model.tray.isEmpty)
        #expect(try comparison.database.tray.all().isEmpty)
        #expect(model.duplicateSets.first?.files.count == 3)
    }
}
