import FileSystemKit
import Foundation
import RakerModel
import Synchronization

/// Builds a `SizeTree` from a walk. Workers append each directory's entries under a lock,
/// so a directory's children always occupy one contiguous index range.
public final class TreeBuilder: WalkSink {
    private let storage = Mutex(Storage())
    private let homeDirectory: String

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    public func begin(rootPath: String) -> UInt32 {
        // The walk reads what's inside the root; the root's own date comes from the root.
        let modified = (try? FileStatus.of(rootPath)).map { $0.modificationTime / 1_000_000_000 } ?? 0
        return storage.withLock { storage in
            storage = Storage()
            storage.appendRoot(name: rootPath, modified: modified)
            return 0
        }
    }

    public func directoryRead(token: UInt32, path: String, batch: EntryBatch, descend: [Int]) -> [UInt32] {
        storage.withLock { storage in
            storage.append(batch, under: token, descend: descend)
        }
    }

    public func directoryFailed(token: UInt32, path: String, error: Int32) {
        let reason: SkippedLocation.Reason
        switch error {
        case EACCES, EPERM:
            reason = .permissionDenied(area: ProtectedArea.classify(path: path, homeDirectory: homeDirectory))
        case ENOENT:
            reason = .notFound
        default:
            reason = .ioError(code: error)
        }
        storage.withLock { storage in
            storage.markUnreadable(token, location: SkippedLocation(path: path, reason: reason))
        }
    }

    /// Aggregates sizes and returns the finished tree. Call once, after the walk.
    public func makeTree(rootPath: String) -> SizeTree {
        storage.withLock { storage in
            let tree = storage.finish(rootPath: rootPath)
            storage = Storage()
            return tree
        }
    }
}

/// Column storage for the tree under construction.
struct Storage: ~Copyable {
    var nameBytes: [UInt8] = []
    var nameOffsets: [UInt32] = []
    var nameLengths: [UInt16] = []
    var parents: [UInt32] = []
    var childStarts: [UInt32] = []
    var childCounts: [UInt32] = []
    var kinds: [EntryKind] = []
    var flags: [EntryFlags] = []
    var logical: [UInt64] = []
    var allocated: [UInt64] = []
    var reclaimable: [UInt64] = []
    var modificationTimes: [Int64] = []
    /// File IDs of multiply-linked files already counted once.
    var linkedFileIDs: Set<UInt64> = []
    var skipped: [SkippedLocation] = []

    mutating func appendRoot(name: String, modified: Int64) {
        appendName(Array(name.utf8)[...])
        parents.append(.max)
        childStarts.append(0)
        childCounts.append(0)
        kinds.append(.directory)
        flags.append([])
        logical.append(0)
        allocated.append(0)
        reclaimable.append(0)
        modificationTimes.append(modified)
    }

    mutating func append(_ batch: EntryBatch, under parent: UInt32, descend: [Int]) -> [UInt32] {
        let start = UInt32(kinds.count)
        childStarts[Int(parent)] = start
        childCounts[Int(parent)] = UInt32(batch.count)

        for index in 0 ..< batch.count {
            let kind = batch.kinds[index]
            var entryFlags = batch.flags[index]
            var entryLogical = batch.logicalSizes[index]
            var entryAllocated = batch.allocatedSizes[index]
            var entryReclaimable = batch.privateSizes[index]

            if kind == .directory {
                // Directory totals come from their children.
                entryLogical = 0
                entryAllocated = 0
                entryReclaimable = 0
            } else if entryFlags.contains(.multiplyLinked) {
                // Count the data once. Removing one link frees nothing while others remain,
                // so hard-linked files never add to the reclaimable lower bound.
                entryReclaimable = 0
                if !linkedFileIDs.insert(batch.fileIDs[index]).inserted {
                    entryFlags.insert(.duplicateHardLink)
                    entryLogical = 0
                    entryAllocated = 0
                }
            }

            appendName(batch.nameUTF8(at: index))
            parents.append(parent)
            childStarts.append(0)
            childCounts.append(0)
            kinds.append(kind)
            flags.append(entryFlags)
            logical.append(entryLogical)
            allocated.append(entryAllocated)
            reclaimable.append(entryReclaimable)
            modificationTimes.append(batch.modificationTimes[index])
        }
        return descend.map { start + UInt32($0) }
    }

    mutating func markUnreadable(_ token: UInt32, location: SkippedLocation) {
        flags[Int(token)].insert(.unreadable)
        skipped.append(location)
    }

    private mutating func appendName(_ bytes: ArraySlice<UInt8>) {
        nameOffsets.append(UInt32(nameBytes.count))
        nameLengths.append(UInt16(clamping: bytes.count))
        nameBytes.append(contentsOf: bytes.prefix(Int(UInt16.max)))
    }

    /// Children always get higher indices than their parent, so one reverse pass adds every
    /// node's totals into its parent.
    mutating func finish(rootPath: String) -> SizeTree {
        var descendants = [UInt32](repeating: 0, count: kinds.count)
        var index = kinds.count - 1
        while index > 0 {
            let parent = Int(parents[index])
            logical[parent] &+= logical[index]
            allocated[parent] &+= allocated[index]
            reclaimable[parent] &+= reclaimable[index]
            descendants[parent] &+= descendants[index] &+ 1
            index -= 1
        }
        return SizeTree(
            rootPath: rootPath,
            nameBytes: nameBytes,
            nameOffsets: nameOffsets,
            nameLengths: nameLengths,
            parents: parents,
            childStarts: childStarts,
            childCounts: childCounts,
            kinds: kinds,
            flags: flags,
            logical: logical,
            allocated: allocated,
            reclaimable: reclaimable,
            modificationTimes: modificationTimes,
            descendants: descendants,
            skipped: skipped
        )
    }
}
