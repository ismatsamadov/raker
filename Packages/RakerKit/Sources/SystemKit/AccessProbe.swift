import Darwin
import Foundation
import RakerModel

/// Checks whether Raker can read protected areas by opening their folders. There's no API
/// that answers this, for Full Disk Access least of all.
public struct AccessProbe: Sendable {
    private let homeDirectory: String

    public init(homeDirectory: String = NSHomeDirectory()) {
        self.homeDirectory = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
    }

    /// Opens the area's folder. If macOS hasn't asked about a Files & Folders area yet, this
    /// makes it ask and blocks until the person answers, so call it off the main thread.
    public func check(_ area: ProtectedArea) -> AccessState {
        guard area.isCheckable, let relative = area.homeRelativePaths.first else { return .unknown }
        let path = homeDirectory + "/" + relative
        // Looking at the folder itself is allowed; reading inside it is what's protected.
        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .absent : .unknown }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .absent }
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            switch errno {
            case EPERM, EACCES: return .denied
            case ENOENT: return .absent
            default: return .unknown
            }
        }
        close(descriptor)
        return .granted
    }

    public func check(_ areas: [ProtectedArea]) -> [ProtectedArea: AccessState] {
        Dictionary(uniqueKeysWithValues: areas.map { ($0, check($0)) })
    }
}
