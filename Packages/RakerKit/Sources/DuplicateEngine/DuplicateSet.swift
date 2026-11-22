import Foundation
import RakerModel

/// One copy in a set of identical files.
public struct DuplicateFile: Sendable, Hashable, Identifiable {
    public var path: String
    public var identity: FileIdentity
    public var modified: Date
    /// Bytes freed if this copy alone is removed: zero for APFS clones and hard links,
    /// which share their data.
    public var reclaimable: UInt64

    public var id: String { path }

    public init(path: String, identity: FileIdentity, modified: Date, reclaimable: UInt64) {
        self.path = path
        self.identity = identity
        self.modified = modified
        self.reclaimable = reclaimable
    }
}

/// Files with byte-for-byte identical content.
public struct DuplicateSet: Sendable, Hashable, Identifiable {
    /// The SHA-256 of the content.
    public var id: String
    /// Size of each copy, as Finder shows it.
    public var size: UInt64
    public var allocatedPerCopy: UInt64
    /// Sorted by path.
    public var files: [DuplicateFile]

    public init(id: String, size: UInt64, allocatedPerCopy: UInt64, files: [DuplicateFile]) {
        self.id = id
        self.size = size
        self.allocatedPerCopy = allocatedPerCopy
        self.files = files.sorted { $0.path < $1.path }
    }

    /// Space freed by removing every copy except `keeper`, counting only data no other file shares.
    public func reclaimable(keeping keeper: String) -> UInt64 {
        files.filter { $0.path != keeper }.reduce(0) { $0 &+ $1.reclaimable }
    }

    /// Every copy shares its data with the others, so removing copies frees nothing.
    public var sharesAllData: Bool {
        files.allSatisfy { $0.reclaimable == 0 }
    }

    /// The findings for removing `selected` copies while `keeper` stays. The keeper is never
    /// included, whatever the selection says.
    public func findings(removing selected: Set<String>, keeping keeper: DuplicateFile) -> [Finding] {
        files.filter { selected.contains($0.path) && $0.path != keeper.path }.map { file in
            Finding(
                id: "duplicates:\(file.path)",
                subject: .file(FileRef(path: file.path, identity: file.identity)),
                category: "duplicates",
                safety: .review,
                size: SizeEstimate(logical: size, allocated: allocatedPerCopy, reclaimable: file.reclaimable),
                evidence: [.duplicateOf(path: keeper.path, identity: keeper.identity)],
                explanation: "An exact copy of \((keeper.path as NSString).lastPathComponent), which stays where it is."
            )
        }
    }
}
