import RakerModel

/// What Raker knows about each protected area: from quiet checks, from what scans could
/// and couldn't read, and from macOS's answers when it asked.
public struct AccessMap: Sendable, Equatable {
    private var states: [ProtectedArea: AccessState] = [:]

    public init() {}

    /// Restores answers saved from `remembered`.
    public init(remembered: [String: String]) {
        for (key, value) in remembered {
            if let area = ProtectedArea(rawValue: key), let state = AccessState(rawValue: value) {
                states[area] = state
            }
        }
    }

    public subscript(area: ProtectedArea) -> AccessState {
        get { states[area] ?? .unknown }
        set { states[area] = newValue }
    }

    /// macOS's answers about Files & Folders areas, worth keeping across launches: they tell
    /// which areas can be checked again without macOS asking. Other areas are either checked
    /// quietly or known only from the latest scans, which would go stale.
    public var remembered: [String: String] {
        var result: [String: String] = [:]
        for (area, state) in states where area.isCheckable && area.permission == .filesAndFolders
            && (state == .granted || state == .denied) {
            result[area.rawValue] = state.rawValue
        }
        return result
    }

    /// Areas that can be checked now without macOS asking anything: the quietly checkable
    /// ones, and Files & Folders areas macOS has already asked about.
    public var areasToCheck: [ProtectedArea] {
        ProtectedArea.allCases.filter { area in
            area.isQuietlyCheckable || (area.isCheckable && (self[area] == .granted || self[area] == .denied))
        }
    }

    /// How much of what a permission covers Raker can read, judged by the areas it can
    /// check. On macOS 27.3 and later a person can give Full Disk Access to some areas only.
    public func coverage(of permission: Permission) -> Coverage {
        let known = ProtectedArea.allCases
            .filter { $0.permission == permission && $0.isCheckable }
            .map { self[$0] }
            .filter { $0 == .granted || $0 == .denied }
        if known.isEmpty { return .unknown }
        if known.allSatisfy({ $0 == .granted }) { return .all }
        if known.allSatisfy({ $0 == .denied }) { return .none }
        return .some
    }

    public enum Coverage: Sendable, Equatable {
        case all
        case some
        case none
        case unknown
    }

    /// Learns from a finished scan of `rootPath`. Areas it couldn't read are denied. Files &
    /// Folders areas inside it that it read are granted; those folders always exist, so a
    /// scan that covered one and didn't skip it read it.
    public mutating func learn(fromScanOf rootPath: String, skipped: [SkippedLocation], homeDirectory: String) {
        let denied = learn(refused: skipped)
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        let root = rootPath.hasSuffix("/") && rootPath.count > 1 ? String(rootPath.dropLast()) : rootPath
        for area in ProtectedArea.allCases where area.permission == .filesAndFolders && !denied.contains(area) {
            guard let relative = area.homeRelativePaths.first else { continue }
            let folder = home + "/" + relative
            if folder == root || folder.hasPrefix(root == "/" ? "/" : root + "/") {
                self[area] = .granted
            }
        }
    }

    /// Learns which areas refused access, from locations a scan couldn't read.
    @discardableResult
    public mutating func learn(refused locations: [SkippedLocation]) -> Set<ProtectedArea> {
        var denied: Set<ProtectedArea> = []
        for location in locations {
            if case .permissionDenied(let area) = location.reason { denied.insert(area) }
        }
        for area in denied {
            self[area] = .denied
        }
        return denied
    }

    /// Learns that a scan couldn't start because macOS refused to let Raker read `rootPath`.
    public mutating func learn(unreadableRoot rootPath: String, homeDirectory: String) {
        let area = ProtectedArea.classify(path: rootPath, homeDirectory: homeDirectory)
        if area.permission == .filesAndFolders || area.isQuietlyCheckable {
            self[area] = .denied
        }
    }
}
