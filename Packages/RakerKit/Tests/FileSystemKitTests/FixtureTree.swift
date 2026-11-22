import Darwin
import Foundation

/// A throwaway folder tree for filesystem tests. Call `remove()` when done.
struct FixtureTree {
    /// Absolute path with symlinks resolved (`/private/var/...`).
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("raker-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        guard let resolved = realpath(base.path, nil) else { throw POSIXError(.ENOENT) }
        path = String(cString: resolved)
        free(resolved)
    }

    func url(_ relative: String) -> URL {
        URL(fileURLWithPath: path).appendingPathComponent(relative)
    }

    func absolute(_ relative: String) -> String {
        path + "/" + relative
    }

    /// Writes a file of exactly `bytes` bytes, creating parent folders as needed.
    func file(_ relative: String, bytes: Int) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A non-zero pattern, so the filesystem can't store it sparsely.
        try Data(repeating: 0x5A, count: bytes).write(to: url)
    }

    func directory(_ relative: String) throws {
        try FileManager.default.createDirectory(at: url(relative), withIntermediateDirectories: true)
    }

    func symlink(_ relative: String, to destination: String) throws {
        try FileManager.default.createSymbolicLink(atPath: absolute(relative), withDestinationPath: destination)
    }

    func hardLink(_ relative: String, to existing: String) throws {
        guard link(absolute(existing), absolute(relative)) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    /// Makes an APFS clone. Returns false where the volume doesn't support cloning.
    func clone(_ relative: String, from existing: String) -> Bool {
        clonefile(absolute(existing), absolute(relative), 0) == 0
    }

    /// Creates nested folders one level at a time, so the total path may exceed `PATH_MAX`.
    func deepDirectories(_ components: [String]) throws {
        var current = open(path, O_RDONLY | O_DIRECTORY)
        guard current >= 0 else { throw POSIXError(.EIO) }
        defer { close(current) }
        for component in components {
            guard mkdirat(current, component, 0o755) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let next = openat(current, component, O_RDONLY | O_DIRECTORY)
            guard next >= 0 else { throw POSIXError(.EIO) }
            close(current)
            current = next
        }
    }

    func setPermissions(_ relative: String, _ mode: mode_t) {
        chmod(absolute(relative), mode)
    }

    func remove() {
        // Restore permissions so locked folders can be deleted.
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let relative as String in enumerator {
                chmod(absolute(relative), 0o755)
            }
        }
        try? FileManager.default.removeItem(atPath: path)
        if FileManager.default.fileExists(atPath: path) {
            // rm walks relative to each folder, so it copes with paths beyond PATH_MAX.
            let rm = Process()
            rm.executableURL = URL(fileURLWithPath: "/bin/rm")
            rm.arguments = ["-rf", path]
            try? rm.run()
            rm.waitUntilExit()
        }
    }
}
