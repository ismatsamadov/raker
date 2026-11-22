import Foundation

/// Turns paths into a canonical form so that different spellings of the same location
/// compare equal.
///
/// - Resolves `.` and `..` and repeated separators lexically, never touching the disk.
/// - Maps aliases: `/var`, `/tmp` and `/etc` are symlinks into `/private`, and paths under
///   `/System/Volumes/Data` are the same items as the firmlinked paths at the root.
/// - The comparison key is NFC-normalized and case-folded, because default APFS volumes
///   are case- and normalization-insensitive: `/SYSTEM` is `/System`.
public enum PathCanonicalizer {
    /// The canonical spelling of an absolute path, or `nil` for a relative path.
    public static func canonicalize(_ path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var components: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(component)
            }
        }
        return "/" + resolvingAliases(components).joined(separator: "/")
    }

    /// A key for comparing paths: canonical, NFC-normalized and case-folded.
    public static func comparisonKey(for path: String) -> String? {
        canonicalize(path).map(fold)
    }

    static func fold(_ string: String) -> String {
        string.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil)
    }

    private static func resolvingAliases(_ components: [Substring]) -> [Substring] {
        guard let first = components.first else { return components }
        let folded = components.prefix(3).map { fold(String($0)) }
        if folded.count == 3, folded == ["system", "volumes", "data"] {
            return Array(components.dropFirst(3))
        }
        switch fold(String(first)) {
        case "var", "tmp", "etc":
            return ["private"] + components
        default:
            return components
        }
    }
}
