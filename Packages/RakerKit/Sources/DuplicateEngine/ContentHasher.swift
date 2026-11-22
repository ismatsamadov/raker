import CryptoKit
import Darwin
import FileSystemKit

/// Hashes file contents for duplicate detection.
///
/// Reads bypass the file cache, so a big comparison doesn't push the user's working files out
/// of memory, and cloud files that aren't on the Mac fail to read instead of being downloaded.
enum ContentHasher {
    static let edgeLength = 16 * 1024

    /// SHA-256 of the first and last 16 KB: cheap, and rules out most files of equal size.
    static func edgeHash(_ path: String, size: UInt64) -> String? {
        withFile(path) { fd in
            var hasher = SHA256()
            let length = Int(min(size, UInt64(edgeLength)))
            guard readChunk(fd, offset: 0, length: length, into: &hasher) else { return nil }
            if size > UInt64(edgeLength * 2) {
                guard readChunk(fd, offset: off_t(size) - off_t(edgeLength), length: edgeLength, into: &hasher) else { return nil }
            }
            return hex(hasher.finalize())
        }
    }

    /// SHA-256 of the whole file.
    static func fullHash(_ path: String, cancellation: CancellationFlag) -> String? {
        withFile(path) { fd in
            var hasher = SHA256()
            let capacity = 1 << 20
            let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 16)
            defer { buffer.deallocate() }
            while true {
                if cancellation.isCancelled { return nil }
                let count = read(fd, buffer, capacity)
                if count < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                if count == 0 { break }
                hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: count))
            }
            return hex(hasher.finalize())
        }
    }

    // MARK: - Helpers

    private static func withFile(_ path: String, _ body: (Int32) -> String?) -> String? {
        // Never download a cloud file just to compare it.
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer {
            setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, max(previous, 0))
        }
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)
        return body(fd)
    }

    private static func readChunk(_ fd: Int32, offset: off_t, length: Int, into hasher: inout SHA256) -> Bool {
        guard length > 0 else { return true }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
        defer { buffer.deallocate() }
        var done = 0
        while done < length {
            let count = pread(fd, buffer + done, length - done, offset + off_t(done))
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { return false }
            done += count
        }
        hasher.update(bufferPointer: UnsafeRawBufferPointer(start: buffer, count: length))
        return true
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(64)
        for byte in digest {
            bytes.append(digits[Int(byte >> 4)])
            bytes.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
