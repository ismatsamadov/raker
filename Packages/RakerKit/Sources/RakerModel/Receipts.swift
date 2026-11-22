import Foundation

/// Why an item was left alone.
public enum SkipReason: Codable, Sendable, Hashable {
    /// The item changed between the scan and the cleanup.
    case changedSinceScan
    /// The item no longer exists.
    case missing
    /// The safety policy doesn't allow removing it this way.
    case protected
    /// The app that uses it is still running.
    case appRunning(bundleID: String)
    /// Synced with iCloud or another provider: removing it here would remove it everywhere.
    case synced
    /// Raker can't carry out this kind of action yet.
    case unsupported
}

/// Why removing an item didn't work.
public enum FailureReason: Codable, Sendable, Hashable {
    case permissionDenied
    /// Locked with the immutable flag.
    case locked
    /// Part of it is on another volume.
    case crossesVolume
    case trashUnavailable
    case ioError(code: Int32)
}

public enum ItemOutcome: Codable, Sendable, Hashable {
    case movedToTrash(trashPath: String)
    case deleted
    case skipped(SkipReason)
    case failed(FailureReason)
}

/// One item of an executed plan.
public struct ExecutedItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var findingID: String
    public var path: String
    public var destination: Destination
    public var size: SizeEstimate
    public var outcome: ItemOutcome
    /// When the item was put back from the Trash.
    public var restoredAt: Date?

    public init(
        id: UUID = UUID(),
        findingID: String,
        path: String,
        destination: Destination,
        size: SizeEstimate,
        outcome: ItemOutcome,
        restoredAt: Date? = nil
    ) {
        self.id = id
        self.findingID = findingID
        self.path = path
        self.destination = destination
        self.size = size
        self.outcome = outcome
        self.restoredAt = restoredAt
    }

    /// Whether the item can be put back: it went to the Trash and hasn't been restored.
    public var isRestorable: Bool {
        if case .movedToTrash = outcome { return restoredAt == nil }
        return false
    }
}

/// What a cleanup did. The receipt screen and History show it.
public struct CleanupReceipt: Codable, Sendable, Identifiable {
    public struct Total: Sendable, Hashable {
        public var count = 0
        public var bytes: UInt64 = 0

        public init() {}

        mutating func add(_ item: ExecutedItem) {
            count += 1
            bytes &+= item.size.allocated
        }
    }

    public var id: UUID
    public var startedAt: Date
    public var finishedAt: Date
    public var items: [ExecutedItem]
    public var spaceBefore: VolumeSpace?
    public var spaceAfter: VolumeSpace?

    public init(
        id: UUID,
        startedAt: Date,
        finishedAt: Date,
        items: [ExecutedItem],
        spaceBefore: VolumeSpace?,
        spaceAfter: VolumeSpace?
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.items = items
        self.spaceBefore = spaceBefore
        self.spaceAfter = spaceAfter
    }

    public var selected: Total { total { _ in true } }
    public var movedToTrash: Total { total { if case .movedToTrash = $0 { true } else { false } } }
    public var deleted: Total { total { $0 == .deleted } }
    public var skipped: Total { total { if case .skipped = $0 { true } else { false } } }
    public var failed: Total { total { if case .failed = $0 { true } else { false } } }

    /// The change in free space measured on the volume; positive means space was freed.
    /// Other activity on the Mac, local snapshots and the Trash all affect it.
    public var observedChange: Int64? {
        guard let before = spaceBefore, let after = spaceAfter else { return nil }
        return Int64(clamping: after.free) - Int64(clamping: before.free)
    }

    private func total(where matches: (ItemOutcome) -> Bool) -> Total {
        var total = Total()
        for item in items where matches(item.outcome) {
            total.add(item)
        }
        return total
    }
}
