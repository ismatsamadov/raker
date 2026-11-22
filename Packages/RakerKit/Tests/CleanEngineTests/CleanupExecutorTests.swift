import Darwin
import FileSystemKit
import Foundation
import Persistence
import RakerModel
import Testing
@testable import CleanEngine

/// Moves items into a folder instead of the real Trash.
private struct FolderTrash: TrashService {
    let folder: String

    func moveToTrash(_ path: String) throws -> String {
        let destination = folder + "/" + UUID().uuidString + "-" + (path as NSString).lastPathComponent
        try FileManager.default.moveItem(atPath: path, toPath: destination)
        return destination
    }

    func restore(_ trashedPath: String, to originalPath: String) throws {
        try FileManager.default.moveItem(atPath: trashedPath, toPath: originalPath)
    }
}

private struct FakeApps: AppDirectory {
    var running: Set<String> = []
    func installedApp(bundleID: String) -> InstalledApp? { nil }
    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }
}

/// A fake home with caches, plus a folder that plays the Trash.
private struct Sandbox {
    let root: String
    var home: String { root + "/home" }
    var trash: String { root + "/Trash" }

    init() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("raker-clean-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = try FileStatus.resolvedPath(base.path)
        try FileManager.default.createDirectory(atPath: trash, withIntermediateDirectories: true)
    }

    func file(_ relative: String, bytes: Int = 10_000) throws -> String {
        let path = home + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: bytes).write(to: URL(fileURLWithPath: path))
        return path
    }

    func finding(_ path: String, safety: SafetyLevel = .regenerable, constraints: [Constraint] = []) throws -> Finding {
        let identity = try FileStatus.of(path).identity
        return Finding(
            id: "test:\(path)",
            subject: .file(FileRef(path: path, identity: identity)),
            category: "caches.apps",
            safety: safety,
            size: SizeEstimate(logical: identity.size, allocated: identity.size, reclaimable: identity.size),
            evidence: [.rule(id: "test")],
            explanation: "Test item",
            constraints: constraints,
            preselected: safety == .regenerable
        )
    }

    func executor(running: Set<String> = [], journal: JournalStore? = nil) -> CleanupExecutor {
        CleanupExecutor(homeDirectory: home, trash: FolderTrash(folder: trash), apps: FakeApps(running: running),
                        journal: journal, volumePath: root)
    }

    func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

@Suite("CleanupExecutor")
struct CleanupExecutorTests {
    @Test("Deletes regenerable items, trashes the rest, and records a receipt")
    func executesPlan() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let cache = try sandbox.file("Library/Caches/com.example.App/data.bin")
        let review = try sandbox.file("Library/Caches/ms-playwright/browser.bin")
        let journal = try JournalStore.inMemory()
        let plan = PlanBuilder.plan(
            for: [try sandbox.finding(cache), try sandbox.finding(review, safety: .review)],
            deleteRegenerable: true, spaceBefore: nil
        )

        let receipt = await sandbox.executor(journal: journal).execute(plan)

        #expect(receipt.deleted.count == 1)
        #expect(receipt.movedToTrash.count == 1)
        #expect(!sandbox.exists(cache))
        #expect(!sandbox.exists(review))
        guard case .movedToTrash(let trashPath) = receipt.items[1].outcome else {
            Issue.record("expected the review item in the Trash")
            return
        }
        #expect(trashPath.hasPrefix(sandbox.trash))
        #expect(try journal.receipt(id: receipt.id)?.items.count == 2)
    }

    @Test("Skips items that changed, disappeared or became symlinks since the scan")
    func identityChecks() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let changed = try sandbox.file("Library/Caches/changed.bin")
        let missing = try sandbox.file("Library/Caches/missing.bin")
        _ = try sandbox.file("Library/Caches/swapped/inner.bin")
        let findings = [
            try sandbox.finding(changed),
            try sandbox.finding(missing),
            try sandbox.finding(sandbox.home + "/Library/Caches/swapped"),
        ]
        try Data(repeating: 0x41, count: 99).write(to: URL(fileURLWithPath: changed))
        try FileManager.default.removeItem(atPath: missing)
        try FileManager.default.removeItem(atPath: sandbox.home + "/Library/Caches/swapped")
        let keep = try sandbox.file("Documents/keep.txt")
        try FileManager.default.createSymbolicLink(atPath: sandbox.home + "/Library/Caches/swapped", withDestinationPath: sandbox.home + "/Documents")

        let receipt = await sandbox.executor().execute(PlanBuilder.plan(for: findings, deleteRegenerable: true, spaceBefore: nil))

        #expect(receipt.items.map(\.outcome) == [
            .skipped(.changedSinceScan), .skipped(.missing), .skipped(.changedSinceScan),
        ])
        #expect(sandbox.exists(changed))
        #expect(sandbox.exists(keep))
    }

    @Test("Never removes what the safety policy protects")
    func policy() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let document = try sandbox.file("Documents/report.pdf")
        let keychain = try sandbox.file("Library/Keychains/login.keychain-db")

        let plan = PlanBuilder.plan(for: [try sandbox.finding(document), try sandbox.finding(keychain)],
                                    deleteRegenerable: true, spaceBefore: nil)
        let receipt = await sandbox.executor().execute(plan)

        #expect(receipt.items.map(\.outcome) == [.skipped(.protected), .skipped(.protected)])
        #expect(sandbox.exists(document))
        #expect(sandbox.exists(keychain))
    }

    @Test("Waits for running apps and never deletes items that need review")
    func constraints() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let running = try sandbox.file("Library/Caches/com.example.App/data.bin")
        let review = try sandbox.file("Library/Caches/review.bin")
        let plan = CleanupPlan(items: [
            PlanItem(finding: try sandbox.finding(running, constraints: [.requiresQuit(bundleID: "com.example.App")]),
                     destination: .delete),
            PlanItem(finding: try sandbox.finding(review, safety: .review), destination: .delete),
        ], spaceBefore: nil)

        let receipt = await sandbox.executor(running: ["com.example.App"]).execute(plan)

        #expect(receipt.items.map(\.outcome) == [.skipped(.appRunning(bundleID: "com.example.App")), .skipped(.unsupported)])
        #expect(sandbox.exists(running))
        #expect(sandbox.exists(review))
    }

    @Test("Never removes synced files, which would remove them on every device")
    func syncedFiles() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let iCloud = try sandbox.file("Library/Mobile Documents/com~apple~CloudDocs/report.pdf")
        let placeholder = try sandbox.file("Movies/clip.mov")
        var marked = try sandbox.finding(placeholder, safety: .review, constraints: [.synced(provider: "cloud")])
        marked.evidence = []
        var cloudFile = try sandbox.finding(iCloud, safety: .review)
        cloudFile.evidence = []
        let plan = PlanBuilder.plan(for: [cloudFile, marked], deleteRegenerable: false, spaceBefore: nil)

        let receipt = await sandbox.executor().execute(plan)

        #expect(receipt.items.map(\.outcome) == [.skipped(.synced), .skipped(.synced)])
        #expect(sandbox.exists(iCloud))
        #expect(sandbox.exists(placeholder))
    }

    @Test("Removes a duplicate only while the copy that stays is there, unchanged and kept")
    func duplicates() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let keeper = try sandbox.file("Pictures/photo.jpg")
        let copy = try sandbox.file("Downloads/photo (1).jpg")
        let keeperIdentity = try FileStatus.of(keeper).identity
        var duplicate = try sandbox.finding(copy, safety: .review)
        duplicate.evidence = [.duplicateOf(path: keeper, identity: keeperIdentity)]
        var keeperFinding = try sandbox.finding(keeper, safety: .review)
        keeperFinding.evidence = [.duplicateOf(path: copy, identity: try FileStatus.of(copy).identity)]

        // Both copies in one plan: neither may go, or no copy would remain.
        let both = await sandbox.executor().execute(PlanBuilder.plan(for: [duplicate, keeperFinding],
                                                                      deleteRegenerable: false, spaceBefore: nil))
        #expect(both.items.map(\.outcome) == [.skipped(.lastCopy), .skipped(.lastCopy)])

        // The kept copy changed since the scan.
        try Data(repeating: 0x42, count: 7).write(to: URL(fileURLWithPath: keeper))
        let changed = await sandbox.executor().execute(PlanBuilder.plan(for: [duplicate], deleteRegenerable: false, spaceBefore: nil))
        #expect(changed.items.map(\.outcome) == [.skipped(.lastCopy)])
        #expect(sandbox.exists(copy))

        // With the kept copy intact, the duplicate goes to the Trash.
        duplicate.evidence = [.duplicateOf(path: keeper, identity: try FileStatus.of(keeper).identity)]
        let done = await sandbox.executor().execute(PlanBuilder.plan(for: [duplicate], deleteRegenerable: false, spaceBefore: nil))
        #expect(done.movedToTrash.count == 1)
        #expect(sandbox.exists(keeper))
        #expect(!sandbox.exists(copy))
    }

    @Test("Preview reports what would happen without changing anything")
    func preview() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let cache = try sandbox.file("Library/Caches/a.bin")
        let document = try sandbox.file("Documents/b.txt")
        let plan = PlanBuilder.plan(for: [try sandbox.finding(cache), try sandbox.finding(document)],
                                    deleteRegenerable: true, spaceBefore: nil)

        #expect(sandbox.executor().preview(plan) == [nil, .protected])
        #expect(sandbox.exists(cache))
    }

    @Test("Restores trashed items once, and never over something new")
    func restore() async throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let first = try sandbox.file("Library/Caches/first.bin")
        let second = try sandbox.file("Library/Caches/second.bin")
        let journal = try JournalStore.inMemory()
        let plan = PlanBuilder.plan(for: [try sandbox.finding(first), try sandbox.finding(second)],
                                    deleteRegenerable: false, spaceBefore: nil)
        let receipt = await sandbox.executor(journal: journal).execute(plan)
        _ = try sandbox.file("Library/Caches/second.bin", bytes: 5)  // something new took its place

        let restorer = Restorer(trash: FolderTrash(folder: sandbox.trash), journal: journal)
        let outcomes = restorer.restoreAll(in: receipt)

        #expect(outcomes[receipt.items[0].id] == .restored)
        #expect(outcomes[receipt.items[1].id] == .originalLocationTaken)
        #expect(sandbox.exists(first))
        let saved = try #require(try journal.receipt(id: receipt.id))
        #expect(saved.items[0].restoredAt != nil)
        #expect(restorer.restore(saved.items[0]) == .notRestorable)
    }
}
