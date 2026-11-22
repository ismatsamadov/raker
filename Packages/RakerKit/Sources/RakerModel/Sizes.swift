/// How much space something takes, measured three ways.
public struct SizeEstimate: Codable, Sendable, Hashable {
    /// The size Finder shows.
    public var logical: UInt64
    /// Blocks on disk; smaller than `logical` for sparse and compressed files.
    public var allocated: UInt64
    /// Bytes freed immediately on deletion: not shared with clones, hard links or snapshots.
    /// A lower bound for folders; `nil` when unknown.
    public var reclaimable: UInt64?

    public init(logical: UInt64, allocated: UInt64, reclaimable: UInt64?) {
        self.logical = logical
        self.allocated = allocated
        self.reclaimable = reclaimable
    }

    public static let zero = SizeEstimate(logical: 0, allocated: 0, reclaimable: 0)
}

/// Capacity of a volume at a moment in time.
public struct VolumeSpace: Codable, Sendable, Hashable {
    public var total: UInt64
    /// Free space, excluding purgeable data.
    public var free: UInt64
    /// What macOS reports as available, including space it can purge on demand.
    public var availableIncludingPurgeable: UInt64

    public init(total: UInt64, free: UInt64, availableIncludingPurgeable: UInt64) {
        self.total = total
        self.free = free
        self.availableIncludingPurgeable = availableIncludingPurgeable
    }

    public var used: UInt64 { total > free ? total - free : 0 }

    public var purgeableEstimate: UInt64 {
        availableIncludingPurgeable > free ? availableIncludingPurgeable - free : 0
    }
}
