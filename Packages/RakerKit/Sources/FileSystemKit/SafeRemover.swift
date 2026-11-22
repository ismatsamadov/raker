import Darwin

/// Why a permanent removal stopped.
public enum RemovalError: Error, Equatable, Sendable {
    case notFound
    case invalidPath
    /// A folder on the way to the item is a symlink.
    case symlinkInPath
    case permissionDenied(path: String)
    /// Locked with the immutable or append-only flag. Raker never clears these flags.
    case locked(path: String)
    /// Part of the item is on another volume.
    case crossesVolume(path: String)
    /// The item changed while it was being removed.
    case changedDuringRemoval(path: String)
    case ioError(path: String, code: Int32)
}

/// What a removal did. When it stops early, `stats` counts what was removed before.
public struct RemovalResult: Sendable, Equatable {
    public var items = 0
    /// Space released, counting hard-linked files only when their last link goes.
    public var allocatedBytes: UInt64 = 0
    public var error: RemovalError?
}

/// Permanently removes files and folders.
///
/// Every step works relative to an open folder descriptor, so a folder swapped for a symlink
/// mid-removal can't redirect it. Symlinks are removed, never followed, and nothing on another
/// volume is touched. Read-only folders the user owns are made writable so their contents can
/// go (as in Go's module cache); immutable files are reported, not unlocked.
public enum SafeRemover {
    public static func remove(_ path: String) -> RemovalResult {
        var result = RemovalResult()
        let components = path.split(separator: "/").map(String.init)
        guard path.hasPrefix("/"), let name = components.last, !components.contains(".."), !components.contains(".") else {
            result.error = .invalidPath
            return result
        }

        // Open the parent one component at a time, refusing symlinks on the way.
        var parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else {
            result.error = .ioError(path: "/", code: errno)
            return result
        }
        for component in components.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            let code = errno
            close(parent)
            guard next >= 0 else {
                switch code {
                case ENOENT: result.error = .notFound
                case ELOOP, ENOTDIR: result.error = .symlinkInPath
                default: result.error = error(for: code, path: path)
                }
                return result
            }
            parent = next
        }
        defer { close(parent) }

        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            result.error = errno == ENOENT ? .notFound : error(for: errno, path: path)
            return result
        }
        var parentInfo = stat()
        guard fstat(parent, &parentInfo) == 0 else {
            result.error = .ioError(path: path, code: errno)
            return result
        }
        if isDirectory(info), info.st_dev != parentInfo.st_dev {
            // The item itself is where another volume is mounted.
            result.error = .crossesVolume(path: path)
            return result
        }
        removeEntry(parent: parent, name: name, info: info, path: path, device: info.st_dev, result: &result)
        return result
    }

    // MARK: - Recursion

    private static func removeEntry(parent: Int32, name: String, info: stat, path: String, device: dev_t, result: inout RemovalResult) {
        if isDirectory(info) {
            guard info.st_dev == device else {
                result.error = .crossesVolume(path: path)
                return
            }
            var fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if fd < 0, errno == EACCES, makeOwnedWritable(parent: parent, name: name, mode: info.st_mode, owner: info.st_uid) {
                fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            }
            guard fd >= 0 else {
                result.error = error(for: errno, path: path)
                return
            }
            // Make sure the folder opened is the one examined.
            var opened = stat()
            guard fstat(fd, &opened) == 0, opened.st_ino == info.st_ino, opened.st_dev == info.st_dev else {
                close(fd)
                result.error = .changedDuringRemoval(path: path)
                return
            }
            removeContents(of: fd, info: opened, path: path, device: device, result: &result)
            close(fd)
            guard result.error == nil else { return }
            unlink(parent: parent, name: name, flags: AT_REMOVEDIR, info: info, path: path, result: &result)
        } else {
            unlink(parent: parent, name: name, flags: 0, info: info, path: path, result: &result)
            if result.error == nil, info.st_nlink <= 1 {
                result.allocatedBytes &+= UInt64(max(0, info.st_blocks)) * 512
            }
        }
    }

    private static func removeContents(of directory: Int32, info: stat, path: String, device: dev_t, result: inout RemovalResult) {
        guard let names = entryNames(of: directory) else {
            result.error = error(for: errno, path: path)
            return
        }
        var madeWritable = false
        for name in names {
            var entry = stat()
            guard fstatat(directory, name, &entry, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { continue }
                result.error = error(for: errno, path: path + "/" + name)
                return
            }
            // Removing entries needs write access to the folder; grant it once if we own it.
            if !madeWritable, info.st_mode & S_IWUSR == 0, info.st_uid == getuid() {
                fchmod(directory, (info.st_mode & 0o7777) | S_IRWXU)
                madeWritable = true
            }
            removeEntry(parent: directory, name: name, info: entry, path: path + "/" + name, device: device, result: &result)
            if result.error != nil { return }
        }
    }

    private static func unlink(parent: Int32, name: String, flags: Int32, info: stat, path: String, result: inout RemovalResult) {
        if unlinkat(parent, name, flags) == 0 {
            result.items += 1
            return
        }
        let code = errno
        if code == EPERM || code == EACCES, info.st_flags & lockedFlags != 0 {
            result.error = .locked(path: path)
        } else if code == ENOENT {
            return
        } else {
            result.error = error(for: code, path: path)
        }
    }

    // MARK: - Helpers

    private static let lockedFlags = UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE) | UInt32(UF_APPEND) | UInt32(SF_APPEND)

    private static func isDirectory(_ info: stat) -> Bool {
        info.st_mode & S_IFMT == S_IFDIR
    }

    /// Adds owner read, write and search permission to a folder the user owns, without
    /// following a symlink.
    private static func makeOwnedWritable(parent: Int32, name: String, mode: mode_t, owner: uid_t) -> Bool {
        guard owner == getuid() else { return false }
        return fchmodat(parent, name, (mode & 0o7777) | S_IRWXU, AT_SYMLINK_NOFOLLOW) == 0
    }

    /// The names in an open folder, excluding "." and "..". Returns nil and sets errno on failure.
    private static func entryNames(of directory: Int32) -> [String]? {
        let copy = dup(directory)
        guard copy >= 0, let stream = fdopendir(copy) else {
            if copy >= 0 { close(copy) }
            return nil
        }
        defer { closedir(stream) }
        var names: [String] = []
        while let entry = readdir(stream) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
                String(decoding: raw.prefix(Int(entry.pointee.d_namlen)), as: UTF8.self)
            }
            if name != ".", name != ".." { names.append(name) }
        }
        return names
    }

    private static func error(for code: Int32, path: String) -> RemovalError {
        switch code {
        case EACCES, EPERM: .permissionDenied(path: path)
        case ENOENT: .notFound
        default: .ioError(path: path, code: code)
        }
    }
}
