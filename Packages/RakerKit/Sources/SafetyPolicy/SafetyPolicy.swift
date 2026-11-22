import Foundation

/// Decides whether a path may ever be removed, independently of any rule or screen.
///
/// The policy lives in code, not in rule packs, and the app and the privileged helper
/// both run it, so neither has to trust the other's checks. It works on canonical,
/// case-folded paths and never touches the disk.
public struct SafetyPolicy: Sendable {
    public enum Verdict: Sendable, Equatable {
        /// Rules may target this path.
        case allowed
        /// Only an explicit user selection may remove this path; rules never target it.
        case selectionOnly(Reason)
        /// Nothing may remove this path.
        case denied(Reason)

        public var permitsRules: Bool { self == .allowed }

        public var permitsUserSelection: Bool {
            if case .denied = self { return false }
            return true
        }
    }

    public enum Reason: String, Sendable, Equatable {
        case notAbsolute
        case volumeRoot
        case systemLocation
        case protectedFolder
        case credentials
        case appDatabases
        case photosLibraryInternals
        case otherUserData
        case personalFiles
        case installedApps
        case syncedFolder
        case userExcluded
        case lockedOriginal
    }

    public let homeDirectory: String
    private let homeKey: String
    private let exclusionKeys: [String]
    private let lockedKeys: [String]

    /// - Parameters:
    ///   - homeDirectory: The home folder of the user the cleanup is for.
    ///   - exclusions: Paths the user excluded from scans and cleanup.
    ///   - lockedOriginals: Files or folders the user marked as originals to keep.
    public init(homeDirectory: String, exclusions: [String] = [], lockedOriginals: [String] = []) {
        self.homeDirectory = homeDirectory
        // An unusable home path must not match anything.
        self.homeKey = PathCanonicalizer.comparisonKey(for: homeDirectory) ?? "/\u{0}"
        self.exclusionKeys = exclusions.compactMap(PathCanonicalizer.comparisonKey(for:))
        self.lockedKeys = lockedOriginals.compactMap(PathCanonicalizer.comparisonKey(for:))
    }

    public func evaluate(_ path: String) -> Verdict {
        guard let key = PathCanonicalizer.comparisonKey(for: path) else { return .denied(.notAbsolute) }

        if lockedKeys.contains(where: { Self.isSameOrInside(key, $0) }) { return .denied(.lockedOriginal) }
        if exclusionKeys.contains(where: { Self.isSameOrInside(key, $0) }) { return .denied(.userExcluded) }
        if key == "/" { return .denied(.volumeRoot) }
        if Self.isInsidePhotosLibrary(key) { return .denied(.photosLibraryInternals) }
        if Self.protectedFolders.contains(key) { return .denied(.protectedFolder) }
        if Self.isSystemLocation(key) { return .denied(.systemLocation) }

        if Self.isSameOrInside(key, homeKey) {
            return key == homeKey ? .denied(.protectedFolder) : evaluateInHome(String(key.dropFirst(homeKey.count + 1)))
        }
        if key.hasPrefix("/users/") {
            return key.hasPrefix("/users/shared/") ? .selectionOnly(.personalFiles) : .denied(.otherUserData)
        }
        if key.hasPrefix("/volumes/") {
            let rest = key.dropFirst("/volumes/".count)
            return rest.contains("/") ? .selectionOnly(.personalFiles) : .denied(.volumeRoot)
        }
        if key.hasPrefix("/applications/") { return .selectionOnly(.installedApps) }
        return .allowed
    }

    // MARK: - Home folder

    private func evaluateInHome(_ relative: String) -> Verdict {
        if Self.protectedFoldersInHome.contains(relative) { return .denied(.protectedFolder) }
        if Self.credentialTreesInHome.contains(where: { Self.isSameOrInside(relative, $0) }) {
            return .denied(.credentials)
        }
        if Self.appDatabaseTreesInHome.contains(where: { Self.isSameOrInside(relative, $0) }) {
            return .denied(.appDatabases)
        }
        if Self.syncedTreesInHome.contains(where: { Self.isSameOrInside(relative, $0) }) {
            return .selectionOnly(.syncedFolder)
        }
        if relative.hasPrefix(".trash/") { return .selectionOnly(.personalFiles) }
        // The Library and tool folders such as ~/.npm hold app data that reviewed rules may target.
        if relative.hasPrefix("library/") || relative.hasPrefix(".") { return .allowed }
        if Self.toolCachesInHome.contains(where: { Self.isSameOrInside(relative, $0) }) { return .allowed }
        return .selectionOnly(.personalFiles)
    }

    // MARK: - Tables (comparison keys: canonical and case-folded)

    /// Folders that must never be removed themselves, whatever happens to their contents.
    static let protectedFolders: Set<String> = [
        "/applications", "/library", "/users", "/users/shared", "/volumes", "/private",
        "/private/var", "/private/tmp", "/private/var/folders", "/opt", "/usr/local",
    ]

    /// System trees that are never removable, with the exceptions below.
    static let systemTrees: [String] = [
        "/system", "/bin", "/sbin", "/usr", "/dev", "/cores", "/private/etc", "/private/var/db",
        "/private/var/vm", "/library/apple", "/.spotlight-v100", "/.fseventsd",
        "/.documentrevisions-v100", "/.vol", "/.file",
    ]

    static let systemTreeExceptions: [String] = ["/usr/local"]

    static let protectedFoldersInHome: Set<String> = [
        "library", "documents", "desktop", "downloads", "pictures", "movies", "music", "public",
        "applications", ".trash", "library/application support", "library/caches",
        "library/containers", "library/group containers", "library/preferences", "library/logs",
        "library/developer", "library/launchagents", "library/saved application state",
        "library/httpstorages", "library/webkit", "library/cookies", "library/mobile documents",
        "library/cloudstorage",
    ]

    static let credentialTreesInHome: [String] = [
        ".ssh", ".gnupg", "library/keychains", "library/application support/com.apple.tcc",
    ]

    static let appDatabaseTreesInHome: [String] = [
        "library/mail", "library/messages", "library/accounts", "library/safari",
        "library/calendars", "library/application support/addressbook",
    ]

    static let syncedTreesInHome: [String] = ["library/mobile documents", "library/cloudstorage"]

    /// Tool caches in ordinary folders of the home folder, which otherwise hold personal files:
    /// Go keeps its module cache in ~/go, next to code people write.
    static let toolCachesInHome: [String] = ["go/pkg/mod"]

    // MARK: - Helpers

    static func isSameOrInside(_ key: String, _ base: String) -> Bool {
        key == base || key.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    static func isSystemLocation(_ key: String) -> Bool {
        if systemTreeExceptions.contains(where: { isSameOrInside(key, $0) }) { return false }
        return systemTrees.contains(where: { isSameOrInside(key, $0) })
    }

    /// True for items inside a Photos library package (the package itself is a personal file).
    static func isInsidePhotosLibrary(_ key: String) -> Bool {
        let components = key.split(separator: "/")
        return components.dropLast().contains { $0.hasSuffix(".photoslibrary") }
    }
}
