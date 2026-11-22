import AppCatalog
import ArgumentParser
import Foundation
import RakerFoundation
import RakerModel
import SystemKit

// MARK: - apps

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List installed apps with their version, where each came from and what it runs on.",
        discussion: "Intel-only apps need Rosetta 2. Read-only."
    )

    @Flag(help: "Sort by size, measuring every app first.")
    var bySize = false

    func run() async throws {
        var apps = AppInventory().apps()
        var sizes: [String: SizeEstimate] = [:]
        if bySize {
            let bundles = apps.map { AppFile(path: $0.path, kind: .application, confidence: .high, isShared: false, reason: .bundle) }
            sizes = await Task.detached { AppFile.measure(bundles) }.value.mapValues(\.size)
            apps.sort { (sizes[$0.path]?.allocated ?? 0) > (sizes[$1.path]?.allocated ?? 0) }
        }
        for app in apps {
            let details = [app.version, app.source.title, app.architecture == .intel ? "Intel only" : nil].compactMap { $0 }
            if bySize {
                print(Output.row(app.name, size: sizes[app.path]?.allocated ?? 0, detail: details.joined(separator: ", ")))
            } else {
                print(app.name.padding(toLength: 40, withPad: " ", startingAt: 0) + " " + details.joined(separator: ", "))
            }
        }
        let intel = apps.filter { $0.architecture == .intel }.count
        print("\n\(apps.count) apps" + (intel > 0 ? ", \(intel) Intel-only" : "") + ". `raker app <name>` lists an app's files.")
    }
}

// MARK: - app

struct AppFiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "List an app's files across your Library, and how sure Raker is that each belongs to it.",
        discussion: "Read-only. ✓ marks what uninstalling would choose for you: certain matches no other app uses."
    )

    @Argument(help: "The app's name or bundle ID.")
    var query: String

    func run() async throws {
        let apps = AppInventory().apps()
        let matches = apps.filter {
            $0.bundleID.caseInsensitiveCompare(query) == .orderedSame || $0.name.localizedCaseInsensitiveContains(query)
        }
        guard let app = matches.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) ?? matches.first else {
            throw ValidationError("No installed app matches \"\(query)\".")
        }
        let rules = (try? loadPack().rules) ?? []
        let files = await Task.detached {
            AssociatedFileFinder(otherApps: apps, rules: rules).files(for: app, identity: AppIdentity.of(app))
        }.value
        let sizes = await Task.detached { AppFile.measure(files) }.value

        print("\(app.name) \(app.version ?? "")  ·  \(app.bundleID)  ·  \(app.source.title)")
        if !app.isRemovable { print("Part of macOS: Raker won't remove it.") }
        for file in files {
            let mark = file.isPreselected ? "✓" : " "
            var detail = "\(file.kind.title), \(file.confidence.title.lowercased()) confidence"
            if file.isShared { detail += ", may be shared" }
            if sizes[file.path]?.isRefused == true { detail += ", not readable without Full Disk Access" }
            print(Output.row("\(mark) \(Text.abbreviated(file.path))", size: sizes[file.path]?.size.allocated ?? 0, detail: detail))
        }
        let total = files.reduce(UInt64(0)) { $0 &+ (sizes[$1.path]?.size.allocated ?? 0) }
        let chosen = files.filter(\.isPreselected).reduce(UInt64(0)) { $0 &+ (sizes[$1.path]?.size.allocated ?? 0) }
        print("\n\(files.count) items, \(ByteCount(total).formatted). Uninstalling would choose \(ByteCount(chosen).formatted). Nothing was changed.")
    }
}

// MARK: - leftovers

struct LeftoverFiles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "leftovers",
        abstract: "List files left behind by apps that are no longer installed.",
        discussion: """
        Only what macOS knew as an app counts: one that had a sandbox or saved windows, or a \
        background agent whose program is gone. Read-only. ✓ marks what cleaning would choose \
        for you: leftovers no installed app could use.
        """
    )

    func run() async throws {
        let groups = await Task.detached {
            let installed = AppInventory().apps().map(AppIdentity.of)
            return LeftoverFinder(apps: LaunchServicesAppDirectory(), installed: installed).leftovers()
        }.value
        let files = groups.flatMap(\.files)
        let sizes = await Task.detached { AppFile.measure(files) }.value
        func size(_ group: Leftovers) -> UInt64 {
            group.files.reduce(UInt64(0)) { $0 &+ (sizes[$1.path]?.size.allocated ?? 0) }
        }

        for group in groups.sorted(by: { size($0) > size($1) }) {
            print(Output.row(group.bundleID, size: size(group), detail: group.files.count == 1 ? "1 item" : "\(group.files.count) items"))
            for file in group.files {
                let mark = file.isPreselected ? "✓" : " "
                var detail = file.kind.title
                if file.isShared { detail += ", may be shared" }
                if sizes[file.path]?.isRefused == true { detail += ", not readable without Full Disk Access" }
                print(Output.row("  \(mark) \(Text.abbreviated(file.path))", size: sizes[file.path]?.size.allocated ?? 0, detail: detail))
            }
        }
        let total = files.reduce(UInt64(0)) { $0 &+ (sizes[$1.path]?.size.allocated ?? 0) }
        let chosen = files.filter(\.isPreselected).reduce(UInt64(0)) { $0 &+ (sizes[$1.path]?.size.allocated ?? 0) }
        print("\n\(groups.count) removed apps, \(files.count) items, \(ByteCount(total).formatted). Cleaning would choose \(ByteCount(chosen).formatted). Nothing was changed.")
    }
}

extension AppBundleInfo.Source {
    var title: String {
        switch self {
        case .appStore: "App Store"
        case .setapp: "Setapp"
        case .apple: "macOS"
        case .direct: "Downloaded"
        }
    }
}

extension AppFile.Kind {
    var title: String {
        switch self {
        case .application: "Application"
        case .supportFiles: "Support files"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .container: "Container"
        case .groupContainer: "Shared container"
        case .savedState: "Saved windows"
        case .webData: "Website data"
        case .logs: "Logs"
        case .launchAgent: "Launch agent"
        case .scripts: "Scripts"
        case .temporary: "Temporary files"
        }
    }
}

extension AppFile.Confidence {
    var title: String {
        switch self {
        case .high: "High"
        case .medium: "Medium"
        case .low: "Low"
        }
    }
}
