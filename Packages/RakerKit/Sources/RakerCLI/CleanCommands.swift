import ArgumentParser
import CleanEngine
import FileSystemKit
import Foundation
import Persistence
import RakerFoundation
import RakerModel
import ScanEngine
import SystemKit

// MARK: - clean

struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Clean caches, temporary files and logs.",
        discussion: """
        Without --execute this only shows what would happen. Items that rebuild automatically \
        are deleted; items that need review are included only with --include-review and always \
        go to the Trash. Every cleanup is recorded, and items in the Trash can be restored.
        """
    )

    @Flag(help: "Also include items that need review. They always go to the Trash.")
    var includeReview = false

    @Flag(help: "Move everything to the Trash instead of deleting items that rebuild automatically.")
    var toTrash = false

    @Flag(help: "Actually clean. Without it, nothing is changed.")
    var execute = false

    @Flag(help: "Don't ask for confirmation.")
    var yes = false

    func run() async throws {
        let apps = LaunchServicesAppDirectory()
        let report = await RuleScanner(pack: try loadPack(), apps: apps).scan()
        let findings = report.findings.filter { $0.preselected || (includeReview && $0.safety == .review) }
        guard !findings.isEmpty else {
            print("Nothing to clean.")
            return
        }

        let plan = PlanBuilder.plan(
            for: findings,
            deleteRegenerable: !toTrash,
            spaceBefore: try? VolumeInfo.space(containing: NSHomeDirectory())
        )
        let journal = execute ? try JournalStore.open() : nil
        let executor = CleanupExecutor(apps: apps, journal: journal)
        printPreview(plan: plan, checks: executor.preview(plan), apps: apps)

        guard execute else {
            print("\nNothing was changed. Run again with --execute to clean.")
            return
        }
        if !yes {
            print("\nType yes to clean: ", terminator: "")
            guard readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "yes" else {
                print("Cancelled. Nothing was changed.")
                return
            }
        }
        let receipt = await executor.execute(plan)
        print("")
        Receipts.print(receipt, apps: apps)
    }

    private func printPreview(plan: CleanupPlan, checks: [SkipReason?], apps: LaunchServicesAppDirectory) {
        var delete = CleanupReceipt.Total()
        var trash = CleanupReceipt.Total()
        var skipped: [SkipReason: CleanupReceipt.Total] = [:]
        for (item, check) in zip(plan.items, checks) {
            let size = item.finding.size.allocated
            if let reason = check {
                skipped[reason, default: .init()].count += 1
                skipped[reason, default: .init()].bytes &+= size
            } else if item.destination == .delete {
                delete.count += 1
                delete.bytes &+= size
            } else {
                trash.count += 1
                trash.bytes &+= size
            }
        }
        print("Clean plan")
        print(Output.row("  Delete permanently (rebuilds automatically)", size: delete.bytes, detail: Receipts.items(delete.count)))
        print(Output.row("  Move to the Trash", size: trash.bytes, detail: Receipts.items(trash.count)))
        for (reason, total) in skipped.sorted(by: { $0.value.bytes > $1.value.bytes }) {
            print(Output.row("  Skip: \(Receipts.describe(reason, apps: apps))", size: total.bytes, detail: Receipts.items(total.count)))
        }
    }
}

// MARK: - history

struct History: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List past cleanups.")

    @Option(name: .shortAndLong, help: "How many cleanups to list.")
    var limit = 10

    func run() throws {
        let receipts = try JournalStore.open().receipts(limit: limit)
        guard !receipts.isEmpty else {
            print("No cleanups yet.")
            return
        }
        let apps = LaunchServicesAppDirectory()
        for (index, receipt) in receipts.enumerated() {
            if index > 0 { print("") }
            Receipts.print(receipt, apps: apps)
        }
    }
}

// MARK: - restore

struct Restore: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Put back the items a cleanup moved to the Trash.",
        discussion: "Items are restored only while they're still in the Trash and nothing else has taken their place."
    )

    @Argument(help: "The cleanup's ID, or its first few characters, as shown by `raker history`.")
    var cleanup: String

    func run() throws {
        let journal = try JournalStore.open()
        let matches = try journal.receipts(limit: 500).filter {
            $0.id.uuidString.lowercased().hasPrefix(cleanup.lowercased())
        }
        guard matches.count == 1, let receipt = matches.first else {
            throw ValidationError(matches.isEmpty ? "No cleanup starts with \(cleanup)." : "\(cleanup) matches more than one cleanup.")
        }
        let outcomes = Restorer(journal: journal).restoreAll(in: receipt)
        guard !outcomes.isEmpty else {
            print("Nothing from this cleanup is waiting in the Trash.")
            return
        }
        let restored = outcomes.values.filter { $0 == .restored }.count
        print("Restored \(restored) of \(outcomes.count) item\(outcomes.count == 1 ? "" : "s").")
        for item in receipt.items {
            guard let outcome = outcomes[item.id], outcome != .restored else { continue }
            print("  \(Text.abbreviated(item.path)): \(Receipts.describe(outcome))")
        }
    }
}

// MARK: - Receipts

enum Receipts {
    static func print(_ receipt: CleanupReceipt, apps: LaunchServicesAppDirectory) {
        let id = receipt.id.uuidString.prefix(8)
        let date = receipt.startedAt.formatted(date: .abbreviated, time: .shortened)
        Swift.print("Cleanup \(id) · \(date)")
        Swift.print(Output.row("  Deleted", size: receipt.deleted.bytes, detail: items(receipt.deleted.count)))
        let restorable = receipt.items.filter(\.isRestorable).count
        let trashDetail = items(receipt.movedToTrash.count) + (restorable > 0 ? ", restore with: raker restore \(id)" : "")
        Swift.print(Output.row("  Moved to the Trash", size: receipt.movedToTrash.bytes, detail: trashDetail))
        Swift.print(Output.row("  Skipped", size: receipt.skipped.bytes, detail: items(receipt.skipped.count)))
        Swift.print(Output.row("  Failed", size: receipt.failed.bytes, detail: items(receipt.failed.count)))
        if let before = receipt.spaceBefore, let after = receipt.spaceAfter, let change = receipt.observedChange {
            let sign = change >= 0 ? "+" : "−"
            Swift.print("  Free space: \(ByteCount(before.free).formatted) → \(ByteCount(after.free).formatted) "
                + "(observed \(sign)\(ByteCount(change.magnitude).formatted))")
        }
        let problems = Dictionary(grouping: receipt.items.filter {
            if case .failed = $0.outcome { true } else if case .skipped = $0.outcome { true } else { false }
        }) { describe($0.outcome, apps: apps) }
        for (reason, group) in problems.sorted(by: { $0.value.count > $1.value.count }) {
            Swift.print("    \(items(group.count)): \(reason)")
        }
    }

    static func items(_ count: Int) -> String {
        "\(count.formatted()) item\(count == 1 ? "" : "s")"
    }

    static func describe(_ outcome: ItemOutcome, apps: LaunchServicesAppDirectory) -> String {
        switch outcome {
        case .movedToTrash: "moved to the Trash"
        case .deleted: "deleted"
        case .skipped(let reason): "skipped, \(describe(reason, apps: apps))"
        case .failed(let reason): "failed, \(describe(reason))"
        }
    }

    static func describe(_ reason: SkipReason, apps: LaunchServicesAppDirectory) -> String {
        switch reason {
        case .changedSinceScan: "changed since the scan"
        case .missing: "already gone"
        case .protected: "protected by the safety policy"
        case .appRunning(let bundleID): "quit \(apps.installedApp(bundleID: bundleID)?.name ?? bundleID) first"
        case .unsupported: "not supported yet"
        }
    }

    static func describe(_ reason: FailureReason) -> String {
        switch reason {
        case .permissionDenied: "no permission"
        case .locked: "locked"
        case .crossesVolume: "part of it is on another volume"
        case .trashUnavailable: "couldn't move it to the Trash"
        case .ioError(let code): "error \(code)"
        }
    }

    static func describe(_ outcome: Restorer.Outcome) -> String {
        switch outcome {
        case .restored: "restored"
        case .notRestorable: "wasn't moved to the Trash"
        case .notInTrash: "no longer in the Trash"
        case .originalLocationTaken: "something else is at the original location now"
        case .failed(let message): message
        }
    }
}
