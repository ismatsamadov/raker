import Foundation
import Synchronization

/// Receives what the walker reads. Called concurrently from worker threads.
public protocol WalkSink: AnyObject, Sendable {
    /// Called once before the walk starts. Returns the token for the root directory.
    func begin(rootPath: String) -> UInt32

    /// Called after directory `token` has been read.
    /// - Parameter descend: Indices of the subdirectories the walker will read next.
    /// - Returns: One token per index in `descend`, in the same order.
    func directoryRead(token: UInt32, path: String, batch: EntryBatch, descend: [Int]) -> [UInt32]

    /// Called when directory `token` couldn't be opened or read completely.
    func directoryFailed(token: UInt32, path: String, error: Int32)
}

/// Lets any thread stop a walk.
public final class CancellationFlag: Sendable {
    private let flag = Atomic<Bool>(false)

    public init() {}

    public func cancel() {
        flag.store(true, ordering: .relaxed)
    }

    public var isCancelled: Bool {
        flag.load(ordering: .relaxed)
    }
}

/// Running totals, safe to read from any thread while a walk is in progress.
public final class WalkCounters: Sendable {
    public struct Snapshot: Sendable, Hashable {
        public var files = 0
        public var directories = 0
        public var allocatedBytes: UInt64 = 0
        public var unreadableDirectories = 0

        public init() {}

        public var items: Int { files + directories }
    }

    private let files = Atomic<Int>(0)
    private let directories = Atomic<Int>(0)
    private let allocatedBytes = Atomic<UInt64>(0)
    private let unreadableDirectories = Atomic<Int>(0)

    public init() {}

    func record(files fileCount: Int, directories directoryCount: Int, allocatedBytes bytes: UInt64) {
        files.wrappingAdd(fileCount, ordering: .relaxed)
        directories.wrappingAdd(directoryCount, ordering: .relaxed)
        allocatedBytes.wrappingAdd(bytes, ordering: .relaxed)
    }

    func recordUnreadableDirectory() {
        unreadableDirectories.wrappingAdd(1, ordering: .relaxed)
    }

    public var snapshot: Snapshot {
        var snapshot = Snapshot()
        snapshot.files = files.load(ordering: .relaxed)
        snapshot.directories = directories.load(ordering: .relaxed)
        snapshot.allocatedBytes = allocatedBytes.load(ordering: .relaxed)
        snapshot.unreadableDirectories = unreadableDirectories.load(ordering: .relaxed)
        return snapshot
    }
}

/// Directories waiting to be read, shared by the worker threads.
///
/// `outstanding` counts directories queued or being read; when it reaches zero the walk
/// is complete and every waiting worker is released.
final class WorkQueue: @unchecked Sendable {
    struct Item: Sendable {
        let token: UInt32
        let path: String
    }

    // All state below is guarded by `condition`.
    private let condition = NSCondition()
    private var items: [Item] = []
    private var outstanding = 0
    private var isClosed = false

    func push(_ newItems: [Item]) {
        guard !newItems.isEmpty else { return }
        condition.lock()
        if !isClosed {
            items.append(contentsOf: newItems)
            outstanding += newItems.count
            condition.broadcast()
        }
        condition.unlock()
    }

    /// Blocks until an item is available. Returns `nil` once the walk is complete or closed.
    func pop() -> Item? {
        condition.lock()
        defer { condition.unlock() }
        while items.isEmpty, !isClosed {
            condition.wait()
        }
        // Last in, first out: depth-first order keeps the queue short.
        return items.popLast()
    }

    /// Marks one popped item as done.
    func finish() {
        condition.lock()
        outstanding -= 1
        if outstanding <= 0 {
            isClosed = true
            condition.broadcast()
        }
        condition.unlock()
    }

    /// Stops the walk: drops queued items and releases every waiting worker.
    func close() {
        condition.lock()
        isClosed = true
        items.removeAll()
        condition.broadcast()
        condition.unlock()
    }
}
