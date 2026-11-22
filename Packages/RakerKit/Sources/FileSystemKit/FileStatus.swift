import Darwin
import Foundation
import RakerModel

/// `lstat` results for one path. Used to resolve scan roots and to re-check an item's
/// identity just before acting on it.
public struct FileStatus: Sendable, Hashable {
    public var device: Int32
    public var inode: UInt64
    public var size: UInt64
    /// Blocks on disk, in bytes.
    public var allocatedSize: UInt64
    /// Nanoseconds since 1970.
    public var modificationTime: Int64
    public var ownerID: uid_t
    public var isDirectory: Bool
    public var isSymlink: Bool

    /// Reads the status of `path` without following a final symlink.
    public static func of(_ path: String) throws(POSIXError) -> FileStatus {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let type = info.st_mode & S_IFMT
        return FileStatus(
            device: info.st_dev,
            inode: info.st_ino,
            size: UInt64(max(0, info.st_size)),
            allocatedSize: UInt64(max(0, info.st_blocks)) * 512,
            modificationTime: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec),
            ownerID: info.st_uid,
            isDirectory: type == S_IFDIR,
            isSymlink: type == S_IFLNK
        )
    }

    public var identity: FileIdentity {
        FileIdentity(device: device, inode: inode, size: size, modificationTime: modificationTime)
    }

    /// The absolute path with every symlink resolved, for example `/tmp` → `/private/tmp`.
    public static func resolvedPath(_ path: String) throws(POSIXError) -> String {
        guard let resolved = realpath(path, nil) else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
