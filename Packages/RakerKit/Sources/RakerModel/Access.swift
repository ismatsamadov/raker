/// Areas that macOS protects separately, each unlocked by a different permission.
public enum ProtectedArea: String, Codable, Sendable, CaseIterable {
    case desktop
    case documents
    case downloads
    case removableVolumes
    case networkVolumes
    case mail
    case messages
    case safari
    case otherAppsData
    case trash
    case deviceBackups
    /// Other Full Disk Access–protected locations in the user's Library.
    case fullDiskAccess
    /// Locations only root can read; the privileged helper can measure them.
    case rootOnly

    /// Best guess at which area protects a path that could not be read.
    public static func classify(path: String, homeDirectory: String) -> ProtectedArea {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        guard path == home || path.hasPrefix(home + "/") else {
            if path.hasPrefix("/Volumes/") { return .removableVolumes }
            return .rootOnly
        }
        let relative = path.dropFirst(home.count)
        let table: [(prefix: String, area: ProtectedArea)] = [
            ("/Desktop", .desktop),
            ("/Documents", .documents),
            ("/Downloads", .downloads),
            ("/.Trash", .trash),
            ("/Library/Mail", .mail),
            ("/Library/Messages", .messages),
            ("/Library/Safari", .safari),
            ("/Library/Containers", .otherAppsData),
            ("/Library/Group Containers", .otherAppsData),
            ("/Library/Application Support/MobileSync", .deviceBackups),
        ]
        for entry in table where relative == entry.prefix || relative.hasPrefix(entry.prefix + "/") {
            return entry.area
        }
        return .fullDiskAccess
    }
}
