import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel

/// An immutable, compact tree of everything a scan found, with folder totals.
///
/// Stored as parallel arrays (about 50 bytes per item plus its name) so millions of items
/// fit comfortably in memory. Index 0 is the scanned root; a directory's children occupy
/// one contiguous index range.
public struct SizeTree: Sendable {
    public typealias Index = Int

    public let rootPath: String
    /// Locations the scan couldn't read.
    public let skipped: [SkippedLocation]

    let nameBytes: [UInt8]
    let nameOffsets: [UInt32]
    let nameLengths: [UInt16]
    let parents: [UInt32]
    let childStarts: [UInt32]
    let childCounts: [UInt32]
    let kinds: [EntryKind]
    let flags: [EntryFlags]
    let logical: [UInt64]
    let allocated: [UInt64]
    let reclaimable: [UInt64]
    let modificationTimes: [Int64]
    let descendants: [UInt32]

    init(
        rootPath: String,
        nameBytes: [UInt8],
        nameOffsets: [UInt32],
        nameLengths: [UInt16],
        parents: [UInt32],
        childStarts: [UInt32],
        childCounts: [UInt32],
        kinds: [EntryKind],
        flags: [EntryFlags],
        logical: [UInt64],
        allocated: [UInt64],
        reclaimable: [UInt64],
        modificationTimes: [Int64],
        descendants: [UInt32],
        skipped: [SkippedLocation]
    ) {
        self.rootPath = rootPath
        self.nameBytes = nameBytes
        self.nameOffsets = nameOffsets
        self.nameLengths = nameLengths
        self.parents = parents
        self.childStarts = childStarts
        self.childCounts = childCounts
        self.kinds = kinds
        self.flags = flags
        self.logical = logical
        self.allocated = allocated
        self.reclaimable = reclaimable
        self.modificationTimes = modificationTimes
        self.descendants = descendants
        self.skipped = skipped
    }

    public var root: Index { 0 }
    public var count: Int { kinds.count }

    public func name(of index: Index) -> String {
        let start = Int(nameOffsets[index])
        return String(decoding: nameBytes[start ..< start + Int(nameLengths[index])], as: UTF8.self)
    }

    public func path(of index: Index) -> String {
        var components: [String] = []
        var current = index
        while current != root {
            components.append(name(of: current))
            current = Int(parents[current])
        }
        return components.reversed().reduce(rootPath) { Paths.join($0, $1) }
    }

    public func parent(of index: Index) -> Index? {
        index == root ? nil : Int(parents[index])
    }

    public func kind(of index: Index) -> EntryKind { kinds[index] }
    public func flags(of index: Index) -> EntryFlags { flags[index] }

    public func size(of index: Index) -> SizeEstimate {
        SizeEstimate(logical: logical[index], allocated: allocated[index], reclaimable: reclaimable[index])
    }

    public func allocatedSize(of index: Index) -> UInt64 { allocated[index] }

    public func modificationDate(of index: Index) -> Date {
        Date(timeIntervalSince1970: TimeInterval(modificationTimes[index]))
    }

    /// Number of items below a directory, at any depth.
    public func descendantCount(of index: Index) -> Int { Int(descendants[index]) }

    public func children(of index: Index) -> Range<Index> {
        let start = Int(childStarts[index])
        return start ..< start + Int(childCounts[index])
    }

    /// Children of a directory, largest first.
    public func largestChildren(of index: Index, limit: Int = .max) -> [Index] {
        let sorted = children(of: index).sorted { allocated[$0] > allocated[$1] }
        return Array(sorted.prefix(limit))
    }

    /// The largest files in the tree, largest first.
    public func largestFiles(limit: Int) -> [Index] {
        guard limit > 0 else { return [] }
        var heap = MinHeap(capacity: limit)
        for index in 0 ..< count where kinds[index] == .file {
            heap.offer(index, weight: allocated[index])
        }
        return heap.drainDescending()
    }

    /// Finds an item by absolute path, if the tree contains it.
    public func index(ofPath path: String) -> Index? {
        guard path.hasPrefix(rootPath) else { return nil }
        var current = root
        for component in path.dropFirst(rootPath.count).split(separator: "/") {
            guard let match = children(of: current).first(where: { name(of: $0) == component }) else {
                return nil
            }
            current = match
        }
        return current
    }
}

/// Keeps the `capacity` heaviest items seen so far.
private struct MinHeap {
    private var items: [(index: Int, weight: UInt64)] = []
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        items.reserveCapacity(capacity)
    }

    mutating func offer(_ index: Int, weight: UInt64) {
        if items.count < capacity {
            items.append((index, weight))
            siftUp(items.count - 1)
        } else if let lightest = items.first, weight > lightest.weight {
            items[0] = (index, weight)
            siftDown(0)
        }
    }

    mutating func drainDescending() -> [Int] {
        items.sorted { $0.weight > $1.weight }.map(\.index)
    }

    private mutating func siftUp(_ start: Int) {
        var child = start
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child].weight < items[parent].weight else { return }
            items.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(_ start: Int) {
        var parent = start
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var smallest = parent
            if left < items.count, items[left].weight < items[smallest].weight { smallest = left }
            if right < items.count, items[right].weight < items[smallest].weight { smallest = right }
            guard smallest != parent else { return }
            items.swapAt(parent, smallest)
            parent = smallest
        }
    }
}
