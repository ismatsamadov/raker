import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import SpaceIndex
import Synchronization

/// Finds files with identical content in a scanned tree.
///
/// Files are grouped by size, then by a hash of their first and last 16 KB, and only then
/// hashed completely, so most files are never read in full. Hard links are one file, not
/// duplicates; APFS clones are reported but free nothing. App bundles, ~/Library, hidden
/// folders and cloud files that aren't on the Mac are left out.
public struct DuplicateFinder: Sendable {
    public struct Options: Sendable, Hashable {
        public var minimumSize: UInt64
        public var homeDirectory: String

        public init(minimumSize: UInt64 = 100_000, homeDirectory: String = NSHomeDirectory()) {
            self.minimumSize = minimumSize
            self.homeDirectory = homeDirectory
        }
    }

    public struct Progress: Sendable, Hashable {
        public var filesHashed = 0
        public var filesToHash = 0
        public var bytesHashed: UInt64 = 0
        public var bytesToHash: UInt64 = 0

        public var fraction: Double {
            bytesToHash == 0 ? 0 : min(1, Double(bytesHashed) / Double(bytesToHash))
        }
    }

    private let options: Options

    public init(options: Options = Options()) {
        self.options = options
    }

    /// Finds duplicate sets, largest saving first. Cancelling the task stops hashing promptly.
    public func find(in tree: SizeTree, onProgress: @escaping @Sendable (Progress) -> Void = { _ in }) async -> [DuplicateSet] {
        let cancellation = CancellationFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Hashing blocks on reads, so it gets its own thread.
                let thread = Thread {
                    continuation.resume(returning: findBlocking(in: tree, cancellation: cancellation, onProgress: onProgress))
                }
                thread.name = "Raker duplicates"
                thread.qualityOfService = .userInitiated
                thread.start()
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    func findBlocking(in tree: SizeTree, cancellation: CancellationFlag, onProgress: @Sendable (Progress) -> Void) -> [DuplicateSet] {
        // 1. Same size.
        let bySize = Dictionary(grouping: candidates(in: tree)) { tree.size(of: $0).logical }.filter { $0.value.count > 1 }
        let sized = bySize.flatMap { size, indices in indices.map { (index: $0, path: tree.path(of: $0), size: size) } }
        guard !sized.isEmpty, !cancellation.isCancelled else { return [] }

        // 2. Same first and last 16 KB.
        let edges = Self.parallelMap(sized, cancellation: cancellation) { ContentHasher.edgeHash($0.path, size: $0.size) }
        var byEdges: [String: [Int]] = [:]
        for (position, hash) in edges.enumerated() {
            guard let hash else { continue }
            byEdges["\(sized[position].size):\(hash)", default: []].append(position)
        }
        let remaining = byEdges.values.filter { $0.count > 1 }.flatMap { $0 }.map { sized[$0] }
        guard !remaining.isEmpty, !cancellation.isCancelled else { return [] }

        // 3. Same full content.
        let initial = Progress(filesToHash: remaining.count, bytesToHash: remaining.reduce(0) { $0 &+ $1.size })
        let reported = Mutex(initial)
        onProgress(initial)
        let full = Self.parallelMap(remaining, cancellation: cancellation) { item -> String? in
            let hash = ContentHasher.fullHash(item.path, cancellation: cancellation)
            let snapshot = reported.withLock { progress -> Progress in
                progress.filesHashed += 1
                progress.bytesHashed &+= item.size
                return progress
            }
            onProgress(snapshot)
            return hash
        }
        guard !cancellation.isCancelled else { return [] }

        var byContent: [String: [Int]] = [:]
        for (position, hash) in full.enumerated() {
            guard let hash else { continue }
            byContent[hash, default: []].append(position)
        }

        // 4. Describe each set, checking the files are still there.
        var sets: [DuplicateSet] = []
        for (hash, positions) in byContent where positions.count > 1 {
            let files = positions.compactMap { position -> DuplicateFile? in
                let item = remaining[position]
                guard let status = try? FileStatus.of(item.path), !status.isSymlink else { return nil }
                return DuplicateFile(
                    path: item.path,
                    identity: status.identity,
                    modified: tree.modificationDate(of: item.index),
                    reclaimable: tree.size(of: item.index).reclaimable ?? 0
                )
            }
            guard files.count > 1, let first = positions.first else { continue }
            let index = remaining[first].index
            sets.append(DuplicateSet(id: hash, size: remaining[first].size, allocatedPerCopy: tree.allocatedSize(of: index), files: files))
        }
        return sets.sorted { lhs, rhs in
            let left = lhs.allocatedPerCopy * UInt64(lhs.files.count - 1)
            let right = rhs.allocatedPerCopy * UInt64(rhs.files.count - 1)
            return left == right ? lhs.id < rhs.id : left > right
        }
    }

    /// Regular files large enough to matter, outside app bundles, ~/Library and hidden folders.
    func candidates(in tree: SizeTree) -> [SizeTree.Index] {
        let library = Paths.join(options.homeDirectory, "Library")
        var result: [SizeTree.Index] = []
        var stack = [tree.root]
        while let current = stack.popLast() {
            for child in tree.children(of: current) {
                let flags = tree.flags(of: child)
                // Hidden items, cloud placeholders and extra links to an already-counted file.
                if flags.contains(.hidden) || flags.contains(.dataless) || flags.contains(.duplicateHardLink) { continue }
                switch tree.kind(of: child) {
                case .directory:
                    let name = tree.name(of: child)
                    if Self.isPackage(name) || tree.path(of: child) == library { continue }
                    stack.append(child)
                case .file:
                    if tree.size(of: child).logical >= options.minimumSize { result.append(child) }
                case .symlink, .other:
                    continue
                }
            }
        }
        return result
    }

    static func isPackage(_ name: String) -> Bool {
        ["app", "photoslibrary", "musiclibrary", "tvlibrary", "bundle", "framework", "plugin", "xcarchive", "pkg", "fcpbundle"]
            .contains(Paths.pathExtension(name))
    }

    /// Runs `transform` over items on a few threads, keeping order.
    private static func parallelMap<Item: Sendable, Result: Sendable>(
        _ items: [Item],
        cancellation: CancellationFlag,
        _ transform: @Sendable (Item) -> Result?
    ) -> [Result?] {
        let results = Mutex([Result?](repeating: nil, count: items.count))
        DispatchQueue.concurrentPerform(iterations: items.count) { index in
            guard !cancellation.isCancelled else { return }
            let value = transform(items[index])
            results.withLock { $0[index] = value }
        }
        return results.withLock { $0 }
    }
}
