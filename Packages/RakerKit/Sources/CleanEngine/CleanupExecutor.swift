import FileSystemKit
import Foundation
import Persistence
import RakerFoundation
import RakerModel
import SafetyPolicy

/// Runs cleanup plans: the only code in Raker that removes anything.
///
/// Every item is checked again just before acting: the safety policy, that it's still the
/// same item the scan saw (device, inode, and for files size and modification time), that it
/// isn't now a symlink, and that apps that use it have quit. Items that fail a check are
/// skipped with a reason; nothing else in the plan stops.
public struct CleanupExecutor: Sendable {
    public struct Progress: Sendable, Hashable {
        public var completed: Int
        public var total: Int
        public var currentPath: String?
    }

    private let policy: SafetyPolicy
    private let trash: any TrashService
    private let apps: any AppDirectory
    private let journal: JournalStore?
    private let volumePath: String
    private let now: @Sendable () -> Date

    public init(
        homeDirectory: String = NSHomeDirectory(),
        exclusions: [String] = [],
        trash: any TrashService = SystemTrash(),
        apps: any AppDirectory,
        journal: JournalStore?,
        volumePath: String? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.policy = SafetyPolicy(homeDirectory: homeDirectory, exclusions: exclusions)
        self.trash = trash
        self.apps = apps
        self.journal = journal
        self.volumePath = volumePath ?? homeDirectory
        self.now = now
    }

    /// What would happen to each item if the plan ran now. Changes nothing.
    public func preview(_ plan: CleanupPlan) -> [SkipReason?] {
        let removing = Self.paths(in: plan)
        return plan.items.map { check($0, removing: removing) }
    }

    /// Runs the plan, saves the receipt to the journal, and returns it.
    public func execute(
        _ plan: CleanupPlan,
        onProgress: @escaping @Sendable (Progress) -> Void = { _ in }
    ) async -> CleanupReceipt {
        await withCheckedContinuation { continuation in
            // Removal blocks on file system calls, so it gets its own thread.
            let thread = Thread {
                continuation.resume(returning: executeBlocking(plan, onProgress: onProgress))
            }
            thread.name = "Raker cleanup"
            thread.qualityOfService = .userInitiated
            thread.start()
        }
    }

    func executeBlocking(_ plan: CleanupPlan, onProgress: @Sendable (Progress) -> Void) -> CleanupReceipt {
        let startedAt = now()
        let spaceBefore = plan.spaceBefore ?? (try? VolumeInfo.space(containing: volumePath))
        let removing = Self.paths(in: plan)
        var executed: [ExecutedItem] = []
        executed.reserveCapacity(plan.items.count)

        for (index, item) in plan.items.enumerated() {
            let path = Self.path(of: item.finding)
            onProgress(Progress(completed: index, total: plan.items.count, currentPath: path))
            let outcome: ItemOutcome
            if let reason = check(item, removing: removing) {
                outcome = .skipped(reason)
            } else {
                outcome = perform(item.destination, on: path ?? "")
            }
            executed.append(ExecutedItem(
                findingID: item.finding.id,
                path: path ?? "",
                destination: item.destination,
                size: item.finding.size,
                outcome: outcome
            ))
        }

        let receipt = CleanupReceipt(
            id: plan.id,
            startedAt: startedAt,
            finishedAt: now(),
            items: executed,
            spaceBefore: spaceBefore,
            spaceAfter: try? VolumeInfo.space(containing: volumePath)
        )
        do {
            try journal?.save(receipt)
        } catch {
            Log.clean.error("Couldn't save the cleanup receipt: \(error.localizedDescription, privacy: .public)")
        }
        onProgress(Progress(completed: plan.items.count, total: plan.items.count, currentPath: nil))
        return receipt
    }

    // MARK: - Checks

    /// Nil when the item may be acted on now; otherwise why it must be skipped.
    /// - Parameter removing: Every path the plan removes, so a duplicate's kept copy is never one of them.
    func check(_ item: PlanItem, removing: Set<String>) -> SkipReason? {
        let finding = item.finding
        guard case .file(let ref) = finding.subject else { return .unsupported }

        switch item.destination {
        case .trash:
            break
        case .delete:
            // Permanent deletion is only ever for data that rebuilds itself.
            guard finding.safety == .regenerable else { return .unsupported }
        case .move, .removeDownload, .action:
            return .unsupported
        }

        // Removing a synced file here would remove it on every device.
        let verdict = policy.evaluate(ref.path)
        let synced = finding.constraints.contains { if case .synced = $0 { true } else { false } }
        if synced || verdict == .selectionOnly(.syncedFolder) { return .synced }

        // Rule findings must be rule targets; anything else needs to be selectable by the user.
        let fromRule = finding.evidence.contains { if case .rule = $0 { true } else { false } }
        guard fromRule ? verdict.permitsRules : verdict.permitsUserSelection else { return .protected }

        let status: FileStatus
        do {
            status = try FileStatus.of(ref.path)
        } catch {
            return error.code == .ENOENT ? .missing : .changedSinceScan
        }
        guard !status.isSymlink,
              status.device == ref.identity.device,
              status.inode == ref.identity.inode
        else { return .changedSinceScan }
        // A folder's own dates change whenever its contents do, so only files are compared further.
        if !status.isDirectory,
           status.size != ref.identity.size || status.modificationTime != ref.identity.modificationTime {
            return .changedSinceScan
        }

        for constraint in finding.constraints {
            if case .requiresQuit(let bundleID) = constraint, apps.isRunning(bundleID: bundleID) {
                return .appRunning(bundleID: bundleID)
            }
        }

        // A duplicate goes only while the copy that stays is still there, unchanged, and kept.
        for evidence in finding.evidence {
            guard case .duplicateOf(let keeperPath, let keeperIdentity) = evidence else { continue }
            guard !removing.contains(keeperPath),
                  let keeper = try? FileStatus.of(keeperPath), !keeper.isSymlink,
                  keeper.identity == keeperIdentity
            else { return .lastCopy }
        }
        return nil
    }

    private static func paths(in plan: CleanupPlan) -> Set<String> {
        Set(plan.items.compactMap { path(of: $0.finding) })
    }

    // MARK: - Actions

    private func perform(_ destination: Destination, on path: String) -> ItemOutcome {
        switch destination {
        case .trash:
            do {
                return .movedToTrash(trashPath: try trash.moveToTrash(path))
            } catch let error as CocoaError {
                switch error.code {
                case .fileNoSuchFile, .fileReadNoSuchFile: return .skipped(.missing)
                case .fileWriteNoPermission, .fileReadNoPermission: return .failed(.permissionDenied)
                default: return .failed(.trashUnavailable)
                }
            } catch {
                return .failed(.trashUnavailable)
            }
        case .delete:
            guard let error = SafeRemover.remove(path).error else { return .deleted }
            switch error {
            case .notFound: return .skipped(.missing)
            case .symlinkInPath, .changedDuringRemoval: return .skipped(.changedSinceScan)
            case .invalidPath: return .skipped(.unsupported)
            case .permissionDenied: return .failed(.permissionDenied)
            case .locked: return .failed(.locked)
            case .crossesVolume: return .failed(.crossesVolume)
            case .ioError(_, let code): return .failed(.ioError(code: code))
            }
        case .move, .removeDownload, .action:
            return .skipped(.unsupported)
        }
    }

    static func path(of finding: Finding) -> String? {
        if case .file(let ref) = finding.subject { return ref.path }
        return nil
    }
}
