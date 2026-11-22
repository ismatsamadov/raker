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

    /// The permission a person gives in System Settings to unlock the area.
    public var permission: Permission {
        switch self {
        case .desktop, .documents, .downloads, .removableVolumes, .networkVolumes: .filesAndFolders
        case .mail, .messages, .safari, .trash, .deviceBackups, .fullDiskAccess: .fullDiskAccess
        case .otherAppsData: .appData
        case .rootOnly: .administrator
        }
    }

    /// Where the area lives, relative to the home folder. The first path is the one whose
    /// readability tells whether Raker has access.
    public var homeRelativePaths: [String] {
        switch self {
        case .desktop: ["Desktop"]
        case .documents: ["Documents"]
        case .downloads: ["Downloads"]
        case .trash: [".Trash"]
        case .mail: ["Library/Mail"]
        case .messages: ["Library/Messages"]
        case .safari: ["Library/Safari"]
        case .otherAppsData: ["Library/Containers", "Library/Group Containers"]
        case .deviceBackups: ["Library/Application Support/MobileSync"]
        case .removableVolumes, .networkVolumes, .fullDiskAccess, .rootOnly: []
        }
    }

    /// Whether opening the area's folder shows if Raker can read it. (Opening the folder
    /// that holds other apps' data shows nothing; the data inside is what's protected.)
    public var isCheckable: Bool {
        !homeRelativePaths.isEmpty && (permission == .filesAndFolders || permission == .fullDiskAccess)
    }

    /// Whether checking is always quiet. Areas under Full Disk Access fail quietly when
    /// access is missing; Files & Folders areas make macOS ask the first time they're read.
    public var isQuietlyCheckable: Bool {
        isCheckable && permission == .fullDiskAccess
    }

    /// Best guess at which area protects a path that could not be read.
    public static func classify(path: String, homeDirectory: String) -> ProtectedArea {
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        guard path == home || path.hasPrefix(home + "/") else {
            if path.hasPrefix("/Volumes/") { return .removableVolumes }
            return .rootOnly
        }
        let relative = path.dropFirst(home.count + 1)
        for area in allCases {
            for prefix in area.homeRelativePaths where relative == prefix || relative.hasPrefix(prefix + "/") {
                return area
            }
        }
        return .fullDiskAccess
    }
}

/// A permission a person gives in System Settings › Privacy & Security.
public enum Permission: String, Codable, Sendable {
    /// Files & Folders. macOS asks the first time Raker reads the folder.
    case filesAndFolders
    /// Full Disk Access. macOS never asks; the person turns it on in System Settings.
    case fullDiskAccess
    /// Access to other apps' data. macOS asks the first time Raker reads it.
    case appData
    /// Only the privileged helper can read these locations.
    case administrator
}

/// Whether Raker can read a protected area.
public enum AccessState: String, Codable, Sendable {
    case granted
    case denied
    /// Not known yet: macOS hasn't asked, or checking would make it ask.
    case unknown
    /// Nothing there on this Mac, such as Mail data when Mail was never set up.
    case absent
}
