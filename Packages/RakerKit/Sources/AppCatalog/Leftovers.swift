import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import RuleEngine

/// What an app that's no longer installed left in the Library.
public struct Leftovers: Sendable, Hashable, Identifiable {
    /// The app's bundle ID, as its files name it.
    public var bundleID: String
    /// Its files, by kind.
    public var files: [AppFile]

    public var id: String { bundleID }

    public init(bundleID: String, files: [AppFile]) {
        self.bundleID = bundleID
        self.files = files
    }
}

/// Finds what removed apps left in the Library: the uninstaller's search, turned around.
///
/// A name alone doesn't make a leftover. Tools and libraries use bundle IDs too, such as
/// SwiftPM's `org.swift.swiftpm`, and Shortcuts keeps its data in
/// `group.is.workflow.shortcuts`. Only IDs macOS knew as apps count: ones with a sandbox
/// container or saved windows, or a background agent whose program is gone. Every file
/// named after such an ID, its helpers or its groups is then listed.
public struct LeftoverFinder: Sendable {
    private let environment: PathEnvironment
    private let resolver: OwnerResolver
    private let installedIDs: Set<String>
    private let installedGroups: Set<String>
    private let installedTeams: Set<String>
    private let installedVendors: Set<String>

    /// - Parameters:
    ///   - apps: Finds apps anywhere on the Mac, not only in the Applications folders. Apps
    ///     in the Trash don't count.
    ///   - installed: The installed apps' identities, whose helpers and groups explain files too.
    public init(environment: PathEnvironment = .current(), apps: any AppDirectory, installed: [AppIdentity]) {
        self.environment = environment
        resolver = OwnerResolver(apps: OutsideTrash(apps: apps))
        installedIDs = Set(installed.flatMap { [$0.bundleID] + $0.helperIDs }.map { $0.lowercased() })
        installedGroups = Set(installed.flatMap(\.appGroups).map { $0.lowercased() })
        installedTeams = Set(installed.compactMap(\.teamID))
        installedVendors = Set(installed.compactMap { Self.vendor(of: $0.bundleID) })
    }

    /// Folders where apps keep items named after their bundle ID or groups, and how the
    /// names end.
    private static let locations: [(folder: String, kind: AppFile.Kind, endings: [String])] = [
        ("~/Library/Containers", .container, [""]),
        ("~/Library/Saved Application State", .savedState, [".savedState"]),
        ("~/Library/Application Support", .supportFiles, [""]),
        ("~/Library/Caches", .caches, [""]),
        ("~/Library/Preferences", .preferences, [".plist"]),
        ("~/Library/Group Containers", .groupContainer, [""]),
        ("~/Library/HTTPStorages", .webData, [".binarycookies", ""]),
        ("~/Library/WebKit", .webData, [""]),
        ("~/Library/Cookies", .webData, [".binarycookies"]),
        ("~/Library/Logs", .logs, [""]),
        ("~/Library/LaunchAgents", .launchAgent, [".plist"]),
        ("~/Library/Application Scripts", .scripts, [""]),
    ]

    /// An item named after an ID no installed app explains.
    private struct Item {
        let path: String
        let kind: AppFile.Kind
        /// The name without its ending.
        let name: String
        /// The app ID the name stands for: for a group, the ID inside it.
        let id: String
        /// The team that owns a group named `TEAMID.…`.
        let team: String?
        let isGroup: Bool

        var key: String { id.lowercased() }
    }

    /// Removed apps and their files, by bundle ID.
    public func leftovers() -> [Leftovers] {
        let items = unexplainedItems()
        // Only apps get a sandbox or saved windows, and an agent whose program is gone was
        // left by software that's gone.
        var proven: [String: String] = [:]
        for item in items where item.kind == .container || item.kind == .savedState
            || (item.kind == .launchAgent && Self.startsMissingProgram(item.path)) {
            proven[item.key] = proven[item.key] ?? item.id
        }

        var files: [String: [AppFile]] = [:]
        for item in items {
            guard let owner = Self.owner(of: item.key, among: proven) else { continue }
            let vendorInstalled = Self.vendor(of: owner).map(installedVendors.contains) ?? false
            let teamInstalled = item.team.map(installedTeams.contains) ?? false
            let reason: AppFile.Reason = item.isGroup ? .appGroup(item.name) : item.key == owner ? .bundleID : .helperID(item.id)
            files[owner, default: []].append(AppFile(path: item.path, kind: item.kind, confidence: .high,
                                                     isShared: vendorInstalled || teamInstalled, reason: reason))
        }
        let order = Dictionary(uniqueKeysWithValues: AppFile.Kind.allCases.enumerated().map { ($1, $0) })
        return files.map { owner, files in
            Leftovers(bundleID: proven[owner] ?? owner, files: files.sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return order[lhs.kind, default: 0] < order[rhs.kind, default: 0] }
                return lhs.path < rhs.path
            })
        }
        .sorted { $0.bundleID.localizedStandardCompare($1.bundleID) == .orderedAscending }
    }

    private func unexplainedItems() -> [Item] {
        var items: [Item] = []
        for location in Self.locations {
            guard let folder = PathPattern.expand(location.folder, in: environment) else { continue }
            for entry in Self.entries(of: folder) {
                guard let ending = location.endings.first(where: { entry.count > $0.count && entry.hasSuffix($0) }),
                      let item = Self.item(named: String(entry.dropLast(ending.count)), at: Paths.join(folder, entry),
                                           kind: location.kind),
                      !isExplained(item)
                else { continue }
                items.append(item)
            }
        }
        return items
    }

    /// The item, if its name stands for an app ID: a bundle ID, a group, or an agent's label.
    private static func item(named name: String, at path: String, kind: AppFile.Kind) -> Item? {
        guard !name.lowercased().contains("com.apple.") else { return nil }
        if kind == .groupContainer || kind == .scripts, let group = group(name) {
            guard OwnerResolver.looksLikeBundleID(group.id) else { return nil }
            return Item(path: path, kind: kind, name: name, id: group.id, team: group.team, isGroup: true)
        }
        let isID = kind == .launchAgent ? name.split(separator: ".").count >= 2 : OwnerResolver.looksLikeBundleID(name)
        return isID ? Item(path: path, kind: kind, name: name, id: name, team: nil, isGroup: false) : nil
    }

    /// Whether an installed app explains the item: the ID is the app's, a helper's or one of
    /// its groups, or extends one, as an extension's container does.
    private func isExplained(_ item: Item) -> Bool {
        if item.isGroup, installedGroups.contains(item.name.lowercased()) { return true }
        let components = item.key.split(separator: ".")
        for length in stride(from: components.count, through: 2, by: -1)
            where installedIDs.contains(components.prefix(length).joined(separator: ".")) {
            return true
        }
        return resolver.owner(ofFolderNamed: item.id).status == .installed
    }

    /// The proven app the key belongs to: the key itself, or the shortest proven ID of three
    /// or more parts it extends.
    private static func owner(of key: String, among proven: [String: String]) -> String? {
        let components = key.split(separator: ".")
        for length in min(3, components.count) ... components.count {
            let candidate = components.prefix(length).joined(separator: ".")
            if proven[candidate] != nil { return candidate }
        }
        return nil
    }

    /// The app ID inside a group's name, `group.com.vendor.App` or `TEAMID.com.vendor.App`,
    /// with the team for the second form.
    static func group(_ name: String) -> (team: String?, id: String)? {
        if name.lowercased().hasPrefix("group.") { return (nil, String(name.dropFirst(6))) }
        let parts = name.split(separator: ".", maxSplits: 1)
        guard parts.count == 2, parts[0].count == 10,
              parts[0].allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// The first two parts of an ID of three or more, such as `com.vendor`.
    static func vendor(of id: String) -> String? {
        let parts = id.lowercased().split(separator: ".")
        return parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil
    }

    /// Whether a launch agent starts a program that's no longer there. Programs on other
    /// volumes, or where macOS keeps Raker out, count as there.
    static func startsMissingProgram(_ plist: String) -> Bool {
        guard let agent = NSDictionary(contentsOfFile: plist) as? [String: Any],
              let program = agent["Program"] as? String ?? (agent["ProgramArguments"] as? [String])?.first,
              program.hasPrefix("/"), !program.hasPrefix("/Volumes/")
        else { return false }
        var info = stat()
        return stat(program, &info) != 0 && errno == ENOENT
    }

    /// Names in a folder, without hidden items or symlinks.
    private static func entries(of folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { name in
            var info = stat()
            return !name.hasPrefix(".") && lstat(Paths.join(folder, name), &info) == 0 && info.st_mode & S_IFMT != S_IFLNK
        }
    }

    /// Whether an app with the ID, or one the ID extends, is installed again, outside the Trash.
    public static func isInstalled(_ bundleID: String, apps: any AppDirectory) -> Bool {
        OwnerResolver(apps: OutsideTrash(apps: apps)).owner(ofFolderNamed: bundleID).status == .installed
    }

    /// IDs of leftover findings whose app is installed again, so they're its data again.
    public static func reinstalled(_ findings: [Finding], apps: any AppDirectory) -> Set<String> {
        Set(findings.filter { finding in
            finding.evidence.contains { evidence in
                guard case .ownerNotInstalled(let bundleID) = evidence else { return false }
                return isInstalled(bundleID, apps: apps)
            }
        }.map(\.id))
    }
}

/// Launch Services still knows apps that were moved to the Trash, but they aren't installed.
struct OutsideTrash: AppDirectory {
    let apps: any AppDirectory

    func installedApp(bundleID: String) -> InstalledApp? {
        guard let app = apps.installedApp(bundleID: bundleID),
              !app.path.contains("/.Trash/"), !app.path.contains("/.Trashes/")
        else { return nil }
        return app
    }

    func isRunning(bundleID: String) -> Bool {
        apps.isRunning(bundleID: bundleID)
    }
}

extension AppFile {
    /// A file a removed app left behind, as a finding. It always goes to the Trash.
    public func finding(leftBy bundleID: String, size: SizeEstimate?) -> Finding? {
        guard let status = try? FileStatus.of(path), !status.isSymlink else { return nil }
        return Finding(
            id: "leftovers:\(path)",
            subject: .file(FileRef(path: path, identity: status.identity)),
            category: CategoryID(rawValue: "apps.\(kind.rawValue)"),
            safety: .review,
            size: size ?? SizeEstimate(logical: status.size, allocated: status.allocatedSize, reclaimable: nil),
            evidence: [.ownerNotInstalled(bundleID: bundleID)],
            explanation: kind.explanation(leftBy: bundleID),
            constraints: [.requiresQuit(bundleID: bundleID)]
        )
    }
}

extension AppFile.Kind {
    /// What a file was for, once its app is gone.
    public func explanation(leftBy bundleID: String) -> String {
        let what = switch self {
        case .application: "the app itself"
        case .supportFiles: "files it kept to work, such as its data and downloads"
        case .caches: "data it kept to work faster"
        case .preferences: "its settings"
        case .container: "its sandbox, with its documents, settings and caches"
        case .groupContainer: "data it shared with its helpers, extensions or other apps"
        case .savedState: "the windows it reopened when it started"
        case .webData: "cookies and website data"
        case .logs: "its logs"
        case .launchAgent: "what started part of it in the background"
        case .scripts: "scripts it was allowed to run"
        case .temporary: "its temporary files"
        }
        return "Left behind by \(bundleID), which is no longer installed: \(what)."
    }
}
