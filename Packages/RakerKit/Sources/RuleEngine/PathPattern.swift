import Darwin
import Foundation

/// Where the per-user locations are on this Mac. Injected so tests can use a fake home.
public struct PathEnvironment: Sendable, Hashable {
    /// The home folder, `~`.
    public var home: String
    /// `$DARWIN_USER_ROOT`: the per-user folder under /private/var/folders that holds the
    /// 0, C, T and X folders.
    public var userRoot: String
    /// `$DARWIN_USER_DIR`: the per-user folder macOS reports as such (the 0 folder).
    public var userDirectory: String
    /// `$DARWIN_USER_TEMP_DIR`: the per-user temporary folder (T).
    public var userTemporary: String
    /// `$DARWIN_USER_CACHE_DIR`: the per-user cache folder (C).
    public var userCache: String

    public init(home: String, userRoot: String, userDirectory: String, userTemporary: String, userCache: String) {
        self.home = home
        self.userRoot = userRoot
        self.userDirectory = userDirectory
        self.userTemporary = userTemporary
        self.userCache = userCache
    }

    /// The real locations for the current user, with symlinks such as /var resolved.
    public static func current() -> PathEnvironment {
        let temporary = configuredPath(_CS_DARWIN_USER_TEMP_DIR) ?? canonical(NSTemporaryDirectory())
        let root = (temporary as NSString).deletingLastPathComponent
        let cache = configuredPath(_CS_DARWIN_USER_CACHE_DIR) ?? temporary
        let directory = configuredPath(_CS_DARWIN_USER_DIR) ?? root
        return PathEnvironment(
            home: canonical(NSHomeDirectory()),
            userRoot: root,
            userDirectory: directory,
            userTemporary: temporary,
            userCache: cache
        )
    }

    func value(of variable: String) -> String? {
        switch variable {
        case "HOME": home
        case "DARWIN_USER_ROOT": userRoot
        case "DARWIN_USER_DIR": userDirectory
        case "DARWIN_USER_TEMP_DIR": userTemporary
        case "DARWIN_USER_CACHE_DIR": userCache
        default: nil
        }
    }

    private static func configuredPath(_ name: Int32) -> String? {
        let length = confstr(name, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(name, &buffer, length) > 0 else { return nil }
        let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return canonical(path)
    }

    /// Resolves symlinks and drops a trailing slash.
    private static func canonical(_ path: String) -> String {
        var result = path
        if let resolved = realpath(path, nil) {
            result = String(cString: resolved)
            free(resolved)
        }
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }
}

/// Path patterns used by rules: `~` or a `$VARIABLE` prefix, and wildcards within components.
public enum PathPattern {
    /// Expands `~` and a leading `$VARIABLE`. Returns `nil` for unknown variables or a
    /// result that isn't absolute.
    public static func expand(_ pattern: String, in environment: PathEnvironment) -> String? {
        let expanded: String
        if pattern == "~" || pattern.hasPrefix("~/") {
            expanded = environment.home + pattern.dropFirst()
        } else if pattern.hasPrefix("$") {
            let end = pattern.firstIndex(of: "/") ?? pattern.endIndex
            guard let value = environment.value(of: String(pattern[pattern.index(after: pattern.startIndex) ..< end])) else {
                return nil
            }
            expanded = value + pattern[end...]
        } else {
            expanded = pattern
        }
        return expanded.hasPrefix("/") ? expanded : nil
    }

    /// Existing items that match an expanded pattern, sorted. Wildcard components are listed
    /// from disk; literal components are checked without following a final symlink.
    public static func existingMatches(of expanded: String) -> [String] {
        var current = ["/"]
        for component in expanded.split(separator: "/") {
            var next: [String] = []
            for base in current {
                if hasWildcard(component) {
                    guard let names = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
                    for name in names where matches(component, name) {
                        next.append(join(base, name))
                    }
                } else {
                    let candidate = join(base, String(component))
                    var info = stat()
                    if lstat(candidate, &info) == 0 { next.append(candidate) }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.sorted()
    }

    /// True when `path` is the item an expanded pattern matches, or is inside one.
    public static func covers(_ expanded: String, path: String) -> Bool {
        let patternComponents = expanded.split(separator: "/")
        let pathComponents = path.split(separator: "/")
        guard pathComponents.count >= patternComponents.count else { return false }
        return zip(patternComponents, pathComponents).allSatisfy { matches($0, String($1)) }
    }

    /// Case-insensitive shell-style matching of one component, as on default APFS volumes.
    public static func matches(_ pattern: Substring, _ name: String) -> Bool {
        fnmatch(String(pattern), name, FNM_CASEFOLD) == 0
    }

    static func hasWildcard(_ component: Substring) -> Bool {
        component.contains { $0 == "*" || $0 == "?" || $0 == "[" }
    }

    static func join(_ base: String, _ name: String) -> String {
        base == "/" ? "/" + name : base + "/" + name
    }
}
