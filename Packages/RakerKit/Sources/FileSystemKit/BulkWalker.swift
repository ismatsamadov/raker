import Darwin
import Foundation
import RakerFoundation

/// Walks a directory tree in parallel and hands each directory's entries to a `WalkSink`.
///
/// - Uses dedicated threads: the blocking system calls never run on Swift's cooperative pool.
/// - Never follows symlinks and doesn't cross mount points unless asked to.
/// - Reads metadata only, so it never downloads cloud files that aren't on the Mac.
public final class BulkWalker: Sendable {
    public struct Options: Sendable {
        public var crossesMountPoints: Bool
        public var workerCount: Int
        public var qualityOfService: QualityOfService

        public init(
            crossesMountPoints: Bool = false,
            workerCount: Int = BulkWalker.defaultWorkerCount,
            qualityOfService: QualityOfService = .userInitiated
        ) {
            self.crossesMountPoints = crossesMountPoints
            self.workerCount = max(1, workerCount)
            self.qualityOfService = qualityOfService
        }
    }

    /// Metadata reads are latency-bound, so a few more threads than cores keeps an SSD busy.
    public static let defaultWorkerCount = min(16, max(4, ProcessInfo.processInfo.activeProcessorCount))

    public let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Walks the tree below `rootPath`, blocking until every directory has been read or
    /// `cancellation` is triggered. Call it from a dedicated thread, never the main thread.
    ///
    /// - Returns: `true` if the walk completed, `false` if it was cancelled.
    @discardableResult
    public func walk(
        rootPath: String,
        sink: some WalkSink,
        counters: WalkCounters = WalkCounters(),
        cancellation: CancellationFlag = CancellationFlag()
    ) -> Bool {
        let queue = WorkQueue()
        queue.push([WorkQueue.Item(token: sink.begin(rootPath: rootPath), path: rootPath)])

        let group = DispatchGroup()
        let options = self.options
        for index in 0 ..< options.workerCount {
            group.enter()
            let thread = Thread {
                Self.runWorker(queue: queue, sink: sink, counters: counters, cancellation: cancellation, options: options)
                group.leave()
            }
            thread.name = "Raker walker \(index + 1)"
            thread.qualityOfService = options.qualityOfService
            thread.start()
        }
        group.wait()
        return !cancellation.isCancelled
    }

    private static func runWorker(
        queue: WorkQueue,
        sink: some WalkSink,
        counters: WalkCounters,
        cancellation: CancellationFlag,
        options: Options
    ) {
        let reader = BulkDirectoryReader()
        var batch = EntryBatch()
        var descend: [Int] = []
        var children: [WorkQueue.Item] = []

        while let item = queue.pop() {
            if cancellation.isCancelled {
                queue.close()
                break
            }
            batch.removeAll()
            descend.removeAll(keepingCapacity: true)
            children.removeAll(keepingCapacity: true)

            let fd = openDirectory(item.path)
            if fd < 0 {
                sink.directoryFailed(token: item.token, path: item.path, error: errno)
                counters.recordUnreadableDirectory()
                queue.finish()
                continue
            }
            let status = reader.read(directory: fd, into: &batch)
            close(fd)
            if status != 0 {
                // Keep whatever was read before the error.
                sink.directoryFailed(token: item.token, path: item.path, error: status)
                counters.recordUnreadableDirectory()
            }

            var fileCount = 0
            var directoryCount = 0
            var bytes: UInt64 = 0
            for index in 0 ..< batch.count {
                if batch.kinds[index] == .directory {
                    directoryCount += 1
                    if options.crossesMountPoints || !batch.flags[index].contains(.mountPoint) {
                        descend.append(index)
                    }
                } else {
                    fileCount += 1
                    bytes &+= batch.allocatedSizes[index]
                }
            }

            let tokens = sink.directoryRead(token: item.token, path: item.path, batch: batch, descend: descend)
            precondition(tokens.count == descend.count, "WalkSink must return one token per subdirectory")
            for (position, index) in descend.enumerated() {
                children.append(WorkQueue.Item(token: tokens[position], path: Paths.join(item.path, batch.name(at: index))))
            }
            counters.record(files: fileCount, directories: directoryCount, allocatedBytes: bytes)
            queue.push(children)
            queue.finish()
        }
    }

    /// Opens a directory without following a symlink in its last component. Paths longer
    /// than `PATH_MAX` are opened one component at a time.
    static func openDirectory(_ path: String) -> Int32 {
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let fd = open(path, flags)
        if fd >= 0 || errno != ENAMETOOLONG { return fd }

        var current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard current >= 0 else { return -1 }
        for component in path.split(separator: "/") {
            let next = openat(current, String(component), flags)
            let code = errno
            close(current)
            guard next >= 0 else {
                errno = code
                return -1
            }
            current = next
        }
        return current
    }
}
