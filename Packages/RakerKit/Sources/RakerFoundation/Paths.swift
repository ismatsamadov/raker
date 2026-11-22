/// Helpers for POSIX paths held as strings.
public enum Paths {
    /// Appends one component to a directory path.
    public static func join(_ directory: String, _ component: String) -> String {
        directory.hasSuffix("/") ? directory + component : directory + "/" + component
    }

    /// The last component of a path ("/a/b.txt" → "b.txt", "/" → "/").
    public static func lastComponent(_ path: String) -> String {
        guard path.count > 1, let slash = path.lastIndex(of: "/") else { return path }
        let next = path.index(after: slash)
        return next == path.endIndex ? path : String(path[next...])
    }

    /// The lowercased extension of a file name without the dot, or "" when there is none.
    /// Names that only start with a dot (".zshrc") have no extension.
    public static func pathExtension(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}
