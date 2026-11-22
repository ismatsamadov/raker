import Foundation

/// How Raker suggests which copy of a duplicate stays.
public enum SurvivorStrategy: String, CaseIterable, Sendable, Codable {
    /// The copy that looks like the original: a name without "copy" or "(1)", outside
    /// Downloads, then the oldest.
    case original
    case oldest
    case newest
    case shortestPath

    public var title: String {
        switch self {
        case .original: "Keep the original"
        case .oldest: "Keep the oldest"
        case .newest: "Keep the newest"
        case .shortestPath: "Keep the shortest path"
        }
    }

    /// The copy to keep. A locked original, or a file inside a locked folder, always wins.
    public func keeper(in set: DuplicateSet, home: String = NSHomeDirectory(), locked: [String] = []) -> DuplicateFile {
        if let original = set.files.first(where: { file in
            locked.contains { file.path == $0 || file.path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        }) {
            return original
        }
        let files = set.files
        let chosen: DuplicateFile?
        switch self {
        case .oldest:
            chosen = files.min { ($0.modified, $0.path) < ($1.modified, $1.path) }
        case .newest:
            chosen = files.min { ($0.modified, $1.path) > ($1.modified, $0.path) }
        case .shortestPath:
            chosen = files.min { ($0.path.count, $0.path) < ($1.path.count, $1.path) }
        case .original:
            let downloads = home + "/Downloads/"
            chosen = files.min { lhs, rhs in
                let left = (Self.looksLikeCopy(lhs.path) ? 1 : 0, lhs.path.hasPrefix(downloads) ? 1 : 0)
                let right = (Self.looksLikeCopy(rhs.path) ? 1 : 0, rhs.path.hasPrefix(downloads) ? 1 : 0)
                if left != right { return left < right }
                return (lhs.modified, lhs.path) < (rhs.modified, rhs.path)
            }
        }
        return chosen ?? files[0]
    }

    /// Names such as "report copy.pdf", "report copy 2.pdf", "report (1).pdf" or "report 2.pdf".
    static func looksLikeCopy(_ path: String) -> Bool {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        let patterns = [#" copy( \d+)?$"#, #" ?\(\d+\)$"#, #" \d{1,2}$"#]
        return patterns.contains { name.range(of: $0, options: .regularExpression) != nil }
    }
}
