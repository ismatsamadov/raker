import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import RuleEngine
import ScanEngine
import Security
import Synchronization

/// Identifiers that tie files to an app.
public struct AppIdentity: Sendable, Hashable {
    public var bundleID: String
    public var names: [String]
    public var teamID: String?
    /// App groups from the app's entitlements; their containers hold the app's shared data.
    public var appGroups: [String]
    /// Bundle IDs of the login items, helpers and XPC services inside the app.
    public var helperIDs: [String]

    public init(bundleID: String, names: [String], teamID: String? = nil, appGroups: [String] = [], helperIDs: [String] = []) {
        self.bundleID = bundleID
        self.names = names
        self.teamID = teamID
        self.appGroups = appGroups
        self.helperIDs = helperIDs
    }

    /// Reads the app's code signature and the bundles embedded in it.
    public static func of(_ app: AppBundleInfo) -> AppIdentity {
        var identity = AppIdentity(bundleID: app.bundleID, names: app.names)
        var code: SecStaticCode?
        var information: CFDictionary?
        if SecStaticCodeCreateWithPath(URL(fileURLWithPath: app.path) as CFURL, [], &code) == errSecSuccess, let code,
           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
           let signing = information as? [String: Any] {
            identity.teamID = signing[kSecCodeInfoTeamIdentifier as String] as? String
            let entitlements = signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
            identity.appGroups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        }
        let embedded = ["Contents/Library/LoginItems", "Contents/XPCServices", "Contents/Library/SystemExtensions",
                        "Contents/Library/LaunchServices", "Contents/Helpers"]
        var helpers: [String] = []
        for folder in embedded {
            let base = Paths.join(app.path, folder)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? [] {
                let plist = NSDictionary(contentsOfFile: Paths.join(base, name + "/Contents/Info.plist"))
                if let id = plist?["CFBundleIdentifier"] as? String {
                    helpers.append(id)
                } else if folder.hasSuffix("LaunchServices"), name.contains(".") {
                    // Privileged helpers are bare executables named after their bundle ID.
                    helpers.append(name)
                }
            }
        }
        identity.helperIDs = helpers.filter { $0 != app.bundleID }.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        return identity
    }
}

/// A file or folder that belongs to an app, and how sure Raker is of that.
public struct AppFile: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case application
        case supportFiles
        case caches
        case preferences
        case container
        case groupContainer
        case savedState
        case webData
        case logs
        case launchAgent
        case scripts
        case temporary
    }

    public enum Confidence: Int, Sendable, Comparable {
        case low
        case medium
        case high

        public static func < (lhs: Confidence, rhs: Confidence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Why Raker thinks it belongs to the app.
    public enum Reason: Sendable, Hashable {
        case bundle
        case bundleID
        case helperID(String)
        case appGroup(String)
        case bundleIDPrefix
        /// A rule in the rule pack says this location belongs to the app.
        case rule(String)
        case name
    }

    public var path: String
    public var kind: Kind
    public var confidence: Confidence
    /// Another installed app may use it too.
    public var isShared: Bool
    public var reason: Reason

    public var id: String { path }

    /// Chosen for you when uninstalling: only certain matches that no other app uses.
    public var isPreselected: Bool { confidence == .high && !isShared }

    public init(path: String, kind: Kind, confidence: Confidence, isShared: Bool, reason: Reason) {
        self.path = path
        self.kind = kind
        self.confidence = confidence
        self.isShared = isShared
        self.reason = reason
    }
}

/// Finds an app's files across the user's Library and per-user folders.
public struct AssociatedFileFinder: Sendable {
    private let environment: PathEnvironment
    private let otherApps: [AppBundleInfo]
    private let rules: [Rule]

    /// - Parameters:
    ///   - otherApps: The other installed apps, to tell when a file may be shared.
    ///   - rules: Rules that name the apps they belong to, such as a browser's cache rule.
    public init(environment: PathEnvironment = .current(), otherApps: [AppBundleInfo], rules: [Rule] = []) {
        self.environment = environment
        self.otherApps = otherApps
        self.rules = rules
    }

    /// The app bundle and its files, most certain first within each kind.
    public func files(for app: AppBundleInfo, identity: AppIdentity) -> [AppFile] {
        var found: [String: AppFile] = [:]
        func add(_ pattern: String, _ kind: AppFile.Kind, _ confidence: AppFile.Confidence, _ reason: AppFile.Reason) {
            guard let expanded = PathPattern.expand(pattern, in: environment) else { return }
            for path in PathPattern.existingMatches(of: expanded) where path != app.path {
                if let existing = found[path], existing.confidence >= confidence { continue }
                found[path] = AppFile(path: path, kind: kind, confidence: confidence,
                                      isShared: isShared(path, reason: reason, app: app), reason: reason)
            }
        }

        for id in [identity.bundleID] + identity.helperIDs where Self.isToken(id) {
            let reason: AppFile.Reason = id == identity.bundleID ? .bundleID : .helperID(id)
            add("~/Library/Application Support/\(id)", .supportFiles, .high, reason)
            add("~/Library/Caches/\(id)", .caches, .high, reason)
            add("~/Library/Preferences/\(id).plist", .preferences, .high, reason)
            add("~/Library/Preferences/ByHost/\(id).*.plist", .preferences, .high, reason)
            add("~/Library/Containers/\(id)", .container, .high, reason)
            add("~/Library/Saved Application State/\(id).savedState", .savedState, .high, reason)
            add("~/Library/HTTPStorages/\(id)", .webData, .high, reason)
            add("~/Library/HTTPStorages/\(id).binarycookies", .webData, .high, reason)
            add("~/Library/WebKit/\(id)", .webData, .high, reason)
            add("~/Library/Cookies/\(id).binarycookies", .webData, .high, reason)
            add("~/Library/Logs/\(id)", .logs, .high, reason)
            add("~/Library/LaunchAgents/\(id).plist", .launchAgent, .high, reason)
            add("~/Library/Application Scripts/\(id)", .scripts, .high, reason)
            add("$DARWIN_USER_CACHE_DIR/\(id)", .caches, .high, reason)
            add("$DARWIN_USER_TEMP_DIR/\(id)", .temporary, .high, reason)
        }
        if Self.isToken(identity.bundleID) {
            // Agents named after the app's ID, such as its updater.
            add("~/Library/LaunchAgents/\(identity.bundleID).*.plist", .launchAgent, .medium, .bundleIDPrefix)
        }
        for group in identity.appGroups where Self.isToken(group) {
            // Declared in the app's own entitlements. Shared only if another app from the vendor is installed.
            add("~/Library/Group Containers/\(group)", .groupContainer, .high, .appGroup(group))
            add("~/Library/Application Scripts/\(group)", .scripts, .high, .appGroup(group))
        }
        for rule in rules where rule.appBundleIDs.contains(identity.bundleID) {
            for target in rule.targets {
                add(target.path, Self.kind(ofCategory: rule.category), .high, .rule(rule.id))
            }
        }
        for name in identity.names where Self.isDistinctive(name) {
            add("~/Library/Application Support/\(name)", .supportFiles, .low, .name)
            add("~/Library/Caches/\(name)", .caches, .low, .name)
            add("~/Library/Logs/\(name)", .logs, .low, .name)
            // "Google Chrome" keeps its files in Google/Chrome.
            let words = name.split(separator: " ", maxSplits: 1).map(String.init)
            if words.count == 2, Self.isToken(words[0]), Self.isToken(words[1]) {
                add("~/Library/Application Support/\(words[0])/\(words[1])", .supportFiles, .medium, .name)
                add("~/Library/Caches/\(words[0])/\(words[1])", .caches, .medium, .name)
                add("~/Library/Logs/\(words[0])/\(words[1])", .logs, .medium, .name)
            }
        }

        let bundle = AppFile(path: app.path, kind: .application, confidence: .high, isShared: false, reason: .bundle)
        let order = Dictionary(uniqueKeysWithValues: AppFile.Kind.allCases.enumerated().map { ($1, $0) })
        return [bundle] + found.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return order[lhs.kind, default: 0] < order[rhs.kind, default: 0] }
            if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
            return lhs.path < rhs.path
        }
    }

    /// Matches named after the app belong to it. Looser ones are shared when another
    /// installed app could explain them: one from the same vendor, or one with the same name.
    private func isShared(_ path: String, reason: AppFile.Reason, app: AppBundleInfo) -> Bool {
        switch reason {
        case .bundle, .bundleID, .helperID, .bundleIDPrefix, .rule:
            return false
        case .appGroup(let group):
            guard !group.localizedCaseInsensitiveContains(app.bundleID) else { return false }
            let vendor = app.bundleID.split(separator: ".").prefix(2).joined(separator: ".")
            return otherApps.contains { $0.bundleID != app.bundleID && $0.bundleID.hasPrefix(vendor + ".") }
        case .name:
            let name = Paths.lastComponent(path)
            return otherApps.contains { other in
                other.bundleID != app.bundleID && other.names.contains { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }
            }
        }
    }

    /// What kind of file a rule's category describes.
    static func kind(ofCategory category: String) -> AppFile.Kind {
        if category.hasPrefix("caches") || category.hasSuffix("caches") { return .caches }
        if category.hasPrefix("logs") { return .logs }
        if category.hasPrefix("temporary") { return .temporary }
        return .supportFiles
    }

    /// Usable inside a path pattern: one component, without wildcard characters.
    static func isToken(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains { "/*?[]".contains($0) }
    }

    /// Specific enough that a folder with this name likely belongs to the app.
    static func isDistinctive(_ name: String) -> Bool {
        let generic: Set<String> = ["data", "cache", "caches", "logs", "support", "updates", "updater", "helper",
                                    "library", "settings", "temp", "plugins", "google", "microsoft", "adobe", "apple"]
        return name.count >= 4 && isToken(name) && !generic.contains(name.lowercased())
    }
}

extension AppFile {
    /// Measures the files, several at a time. A measurement says when macOS kept Raker out.
    /// Blocks; call it off the main thread.
    public static func measure(_ files: [AppFile]) -> [String: PathMeasurement] {
        let results = Mutex([String: PathMeasurement]())
        DispatchQueue.concurrentPerform(iterations: files.count) { index in
            let path = files[index].path
            if let measurement = PathMeasurer.measure(path, workerCount: 2) {
                results.withLock { $0[path] = measurement }
            }
        }
        return results.withLock { $0 }
    }

    /// The file as a finding, ready to stage. It always goes to the Trash, and only while
    /// the app isn't running.
    public func finding(for app: AppBundleInfo, size: SizeEstimate?) -> Finding? {
        guard let status = try? FileStatus.of(path), !status.isSymlink else { return nil }
        return Finding(
            id: "apps:\(path)",
            subject: .file(FileRef(path: path, identity: status.identity)),
            category: CategoryID(rawValue: "apps.\(kind.rawValue)"),
            safety: .review,
            size: size ?? SizeEstimate(logical: status.size, allocated: status.allocatedSize, reclaimable: nil),
            evidence: [.owner(name: app.name, bundleID: app.bundleID)],
            explanation: kind.explanation(appName: app.name),
            constraints: [.requiresQuit(bundleID: app.bundleID)]
        )
    }
}

extension AppFile.Kind {
    public func explanation(appName name: String) -> String {
        switch self {
        case .application: "The \(name) app itself."
        case .supportFiles: "Files \(name) keeps to work, such as its data and downloads."
        case .caches: "Data \(name) keeps to work faster."
        case .preferences: "\(name)'s settings."
        case .container: "\(name)'s sandbox: its documents, settings and caches."
        case .groupContainer: "Data \(name) shares with its helpers, extensions or other apps."
        case .savedState: "The windows \(name) reopens when it starts."
        case .webData: "Cookies and website data from \(name)."
        case .logs: "\(name)'s logs."
        case .launchAgent: "Starts part of \(name) in the background, such as an updater."
        case .scripts: "Scripts \(name) is allowed to run."
        case .temporary: "\(name)'s temporary files."
        }
    }
}
