/// Identifies the exact file a finding was made about, so the executor can refuse to act
/// if the item changed between scan and cleanup.
public struct FileIdentity: Codable, Sendable, Hashable {
    public var device: Int32
    public var inode: UInt64
    public var size: UInt64
    /// Modification time in nanoseconds since 1970.
    public var modificationTime: Int64

    public init(device: Int32, inode: UInt64, size: UInt64, modificationTime: Int64) {
        self.device = device
        self.inode = inode
        self.size = size
        self.modificationTime = modificationTime
    }
}

/// What to remove at a path.
public enum RemovalScope: Codable, Sendable, Hashable {
    /// The item itself.
    case item
    /// The folder's contents; the folder stays.
    case contents
}

public struct FileRef: Codable, Sendable, Hashable {
    public var path: String
    public var identity: FileIdentity
    public var scope: RemovalScope

    public init(path: String, identity: FileIdentity, scope: RemovalScope = .item) {
        self.path = path
        self.identity = identity
        self.scope = scope
    }
}

/// A location a scan could not read, and why.
public struct SkippedLocation: Codable, Sendable, Hashable {
    public enum Reason: Codable, Sendable, Hashable {
        /// macOS privacy protection or file permissions refused access.
        case permissionDenied(area: ProtectedArea)
        case notFound
        case ioError(code: Int32)
    }

    public var path: String
    public var reason: Reason

    public init(path: String, reason: Reason) {
        self.path = path
        self.reason = reason
    }
}
