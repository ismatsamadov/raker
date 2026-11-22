import FileSystemKit
import Foundation
import RakerModel
import Synchronization

/// Totals for one location, measured without building a tree.
public struct PathMeasurement: Sendable, Hashable {
    public var size: SizeEstimate
    /// Files and folders inside, plus the item itself.
    public var items: Int
    /// Newest modification time of anything inside, in seconds since 1970.
    public var newestModification: Int64
    /// Part of the location couldn't be read, so the totals are a lower bound.
    public var isPartial: Bool
    /// macOS privacy protection or file permissions refused access to the location itself.
    public var isRefused = false

    public var newestModificationDate: Date {
        Date(timeIntervalSince1970: TimeInterval(newestModification))
    }
}

public enum PathMeasurer {
    /// Measures a file or folder. Blocks; call it from a dedicated thread.
    public static func measure(_ path: String, workerCount: Int = 4) -> PathMeasurement? {
        guard let status = try? FileStatus.of(path), !status.isSymlink else { return nil }
        let modified = status.modificationTime / 1_000_000_000
        guard status.isDirectory else {
            let size = SizeEstimate(logical: status.size, allocated: status.allocatedSize, reclaimable: status.allocatedSize)
            return PathMeasurement(size: size, items: 1, newestModification: modified, isPartial: false)
        }
        let accumulator = SizeAccumulator(rootPath: path, rootModification: modified)
        BulkWalker(options: .init(workerCount: workerCount)).walk(rootPath: path, sink: accumulator)
        return accumulator.measurement
    }
}

/// A walk sink that only adds things up.
final class SizeAccumulator: WalkSink {
    private struct State {
        var logical: UInt64 = 0
        var allocated: UInt64 = 0
        var reclaimable: UInt64 = 0
        var items = 1
        var newest: Int64 = 0
        var linkedFileIDs = Set<UInt64>()
        var isPartial = false
        var isRefused = false
    }

    private let rootPath: String
    private let state: Mutex<State>

    init(rootPath: String, rootModification: Int64) {
        self.rootPath = rootPath
        var initial = State()
        initial.newest = rootModification
        state = Mutex(initial)
    }

    func begin(rootPath: String) -> UInt32 { 0 }

    func directoryRead(token: UInt32, path: String, batch: EntryBatch, descend: [Int]) -> [UInt32] {
        state.withLock { state in
            for index in 0 ..< batch.count {
                state.items += 1
                state.newest = max(state.newest, batch.modificationTimes[index])
                guard batch.kinds[index] != .directory else { continue }
                if batch.flags[index].contains(.multiplyLinked) {
                    // Count hard-linked data once, and never as reclaimable.
                    guard state.linkedFileIDs.insert(batch.fileIDs[index]).inserted else { continue }
                } else {
                    state.reclaimable &+= batch.privateSizes[index]
                }
                state.logical &+= batch.logicalSizes[index]
                state.allocated &+= batch.allocatedSizes[index]
            }
        }
        return descend.map { _ in 0 }
    }

    func directoryFailed(token: UInt32, path: String, error: Int32) {
        let refused = path == rootPath && (error == EPERM || error == EACCES)
        state.withLock { state in
            state.isPartial = true
            state.isRefused = state.isRefused || refused
        }
    }

    var measurement: PathMeasurement {
        state.withLock { state in
            PathMeasurement(
                size: SizeEstimate(logical: state.logical, allocated: state.allocated, reclaimable: state.reclaimable),
                items: state.items,
                newestModification: state.newest,
                isPartial: state.isPartial,
                isRefused: state.isRefused
            )
        }
    }
}
