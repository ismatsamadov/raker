import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import SpaceIndex

/// What to scan.
public struct ScanScope: Sendable, Hashable {
    public var path: String
    public var crossesMountPoints: Bool

    public init(path: String, crossesMountPoints: Bool = false) {
        self.path = path
        self.crossesMountPoints = crossesMountPoints
    }
}

/// Live progress, delivered about ten times a second.
public struct ScanProgress: Sendable, Hashable {
    public var counters: WalkCounters.Snapshot
    public var elapsed: Duration

    public init(counters: WalkCounters.Snapshot, elapsed: Duration) {
        self.counters = counters
        self.elapsed = elapsed
    }
}

public struct ScanReport: Sendable {
    public let scope: ScanScope
    public let tree: SizeTree
    public let duration: Duration
    /// False if the scan was cancelled; the tree then holds partial results.
    public let completed: Bool
    public var skipped: [SkippedLocation] { tree.skipped }
}

public enum ScanError: Error, Equatable, Sendable {
    case rootNotFound(String)
    case rootNotDirectory(String)
    case rootUnreadable(String, POSIXErrorCode)
}

/// Scans a folder or volume and builds its size tree.
public struct ScanEngine: Sendable {
    private let workerCount: Int
    private let homeDirectory: String

    public init(workerCount: Int = BulkWalker.defaultWorkerCount, homeDirectory: String = NSHomeDirectory()) {
        self.workerCount = workerCount
        self.homeDirectory = homeDirectory
    }

    /// Scans `scope`. Cancelling the calling task stops the scan promptly; the report then
    /// has `completed == false` and holds what was read so far.
    public func scan(
        _ scope: ScanScope,
        onProgress: @escaping @Sendable (ScanProgress) -> Void = { _ in }
    ) async throws(ScanError) -> ScanReport {
        let rootPath = try Self.resolveRoot(scope.path)
        let walker = BulkWalker(options: .init(crossesMountPoints: scope.crossesMountPoints, workerCount: workerCount))
        let builder = TreeBuilder(homeDirectory: homeDirectory)
        let counters = WalkCounters()
        let cancellation = CancellationFlag()
        let clock = ContinuousClock()
        let start = clock.now

        let completed = await withTaskCancellationHandler {
            await withTaskGroup(of: Bool?.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        // The walk blocks, so it gets a thread of its own.
                        let thread = Thread {
                            let finished = walker.walk(
                                rootPath: rootPath, sink: builder, counters: counters, cancellation: cancellation)
                            continuation.resume(returning: finished)
                        }
                        thread.name = "Raker scan coordinator"
                        thread.start()
                    }
                }
                group.addTask {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(100))
                        onProgress(ScanProgress(counters: counters.snapshot, elapsed: clock.now - start))
                    }
                    return nil
                }
                var result = false
                for await value in group {
                    if let finished = value {
                        result = finished
                        group.cancelAll()
                    }
                }
                return result
            }
        } onCancel: {
            cancellation.cancel()
        }

        let duration = clock.now - start
        onProgress(ScanProgress(counters: counters.snapshot, elapsed: duration))
        let tree = builder.makeTree(rootPath: rootPath)
        Log.scan.info("Scanned \(tree.count) items in \(duration.formatted(), privacy: .public)")
        return ScanReport(scope: scope, tree: tree, duration: duration, completed: completed)
    }

    /// Resolves symlinks in the root (such as `/tmp`) and checks that it's a readable folder.
    static func resolveRoot(_ path: String) throws(ScanError) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let resolved: String
        do {
            resolved = try FileStatus.resolvedPath(expanded)
        } catch {
            throw error.code == .ENOENT ? .rootNotFound(expanded) : .rootUnreadable(expanded, error.code)
        }
        let status: FileStatus
        do {
            status = try FileStatus.of(resolved)
        } catch {
            throw .rootUnreadable(resolved, error.code)
        }
        guard status.isDirectory else { throw .rootNotDirectory(resolved) }
        return resolved
    }
}
