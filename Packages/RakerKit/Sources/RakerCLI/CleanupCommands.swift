import ArgumentParser
import Foundation
import RakerFoundation
import RakerModel
import RuleEngine
import SafetyPolicy
import ScanEngine
import SystemKit

// MARK: - junk

struct Junk: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List caches, temporary files and logs, what each one is, and whether it rebuilds itself.",
        discussion: "Read-only: nothing is removed."
    )

    @Flag(help: "List every item, not just the largest few per group.")
    var all = false

    @Flag(help: "Print JSON instead of text.")
    var json = false

    private var apps: LaunchServicesAppDirectory { Self.sharedApps }
    private static let sharedApps = LaunchServicesAppDirectory()

    func run() async throws {
        let pack = try loadPack()
        let rules = StoredRules.load()
        let report = await RuleScanner(pack: pack, apps: apps, exclusions: rules.exclusions,
                                       lockedOriginals: rules.lockedOriginals).scan()
        if json {
            try Output.printJSON(JunkJSON(report: report))
            return
        }
        print("Caches, temporary files and logs (rules \(report.packVersion), \(Text.seconds(report.duration)))")
        for level in [SafetyLevel.regenerable, .review, .expert] {
            let groups = report.groups.filter { $0.rule.safety.level == level }
            guard !groups.isEmpty else { continue }
            print("\n\(Text.title(of: level).uppercased())  ·  \(ByteCount(report.allocatedBytes(safety: level)).formatted)")
            for group in groups {
                printGroup(group)
            }
        }
        if report.groups.isEmpty { print("\nNothing found.") }
        printUnreadable(report.unreadable)
        print("\nNothing was removed. `raker explain <path>` describes any location.")
    }

    private func printUnreadable(_ locations: [SkippedLocation]) {
        guard !locations.isEmpty else { return }
        print("\nNOT READABLE  ·  \(locations.count.formatted()) location\(locations.count == 1 ? "" : "s")")
        print("    macOS's privacy protection kept Raker out. Full Disk Access for the app running this")
        print("    command (System Settings › Privacy & Security) lets Raker measure them.")
        let shown = all ? locations : Array(locations.prefix(5))
        for location in shown {
            print("      " + Text.abbreviated(location.path))
        }
        if locations.count > shown.count {
            print("      \(locations.count - shown.count) more; --all lists every one")
        }
    }

    private func printGroup(_ group: RuleFindingGroup) {
        var detail = "\(group.findings.count.formatted()) item\(group.findings.count == 1 ? "" : "s")"
        if group.reclaimableBytes < group.allocatedBytes / 10 * 9 {
            detail += ", frees about \(ByteCount(group.reclaimableBytes).formatted)"
        }
        let quit = Set(group.findings.flatMap(\.constraints).compactMap { constraint -> String? in
            if case .requiresQuit(let bundleID) = constraint { return bundleID }
            return nil
        })
        if !quit.isEmpty {
            let names = quit.map { apps.installedApp(bundleID: $0)?.name ?? $0 }.sorted()
            detail += ", quit \(names.joined(separator: " and ")) first"
        }
        print(Output.row("  " + group.rule.title, size: group.allocatedBytes, detail: detail))
        print("    " + group.rule.explanation)

        let shown = all ? group.findings : Array(group.findings.prefix(group.rule.identifiesOwners ? 6 : 0))
        if all {
            for finding in shown {
                print(Output.row("      " + Text.path(finding), size: finding.size.allocated, detail: Text.owner(finding) ?? ""))
            }
        } else if !shown.isEmpty {
            let names = shown.map { "\(Text.owner($0) ?? Text.name($0)) \(ByteCount($0.size.allocated).formatted)" }
            let more = group.findings.count > shown.count ? " · \(group.findings.count - shown.count) more" : ""
            print("    " + names.joined(separator: " · ") + more)
        }
    }
}

// MARK: - explain

struct Explain: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Explain what a file or folder is, who it belongs to, and whether it's safe to remove."
    )

    @Argument(help: "The file or folder to explain.")
    var path: String

    func run() async throws {
        let absolute = Text.absolute(path)
        let explainer = LocationExplainer(pack: try loadPack(), apps: LaunchServicesAppDirectory())
        let explanation = await Task.detached { explainer.explain(absolute) }.value

        print(Text.abbreviated(absolute))
        if let rule = explanation.rule {
            field("What it is", "\(rule.title). \(rule.explanation)")
            field("If removed", rule.ifRemoved)
            field("Safety", "\(Text.title(of: rule.safety.level)) (rule \(rule.id))")
        } else if let known = explanation.knownLocation, explanation.knownLocationIsExact {
            field("What it is", "\(known.title). \(known.explanation)")
        } else {
            field("What it is", "No rule describes this location yet.")
            if let known = explanation.knownLocation {
                field("Inside", "\(known.title). \(known.explanation)")
            }
        }
        if explanation.owner.status != .unknown {
            field("Belongs to", Text.describe(explanation.owner))
        }
        if let measurement = explanation.measurement {
            var size = "\(ByteCount(measurement.size.allocated).formatted) on disk"
            if let reclaimable = measurement.size.reclaimable {
                size += ", frees at least \(ByteCount(reclaimable).formatted)"
            }
            size += ", \(measurement.items.formatted()) item\(measurement.items == 1 ? "" : "s")"
            size += ", changed \(measurement.newestModificationDate.formatted(.relative(presentation: .named)))"
            if measurement.isPartial { size += " (some parts couldn't be read)" }
            field("Size", size)
        } else {
            field("Size", "Doesn't exist or can't be read.")
        }
        field("Policy", Text.describe(explanation.verdict))
        if let known = explanation.knownLocation, explanation.knownLocationIsExact, !known.removable {
            field("", "Raker never removes this folder as a whole, only parts a rule describes.")
        }
    }

    private func field(_ label: String, _ value: String) {
        print("  " + label.padding(toLength: 12, withPad: " ", startingAt: 0) + value)
    }
}

// MARK: - Helpers

func loadPack() throws -> RulePack {
    do {
        return try RulePackLoader.baseline()
    } catch {
        throw ValidationError(error.description)
    }
}

enum Text {
    static func title(of level: SafetyLevel) -> String {
        switch level {
        case .regenerable: "Rebuilds automatically"
        case .review: "Needs your review"
        case .expert: "Expert"
        }
    }

    static func seconds(_ duration: Duration) -> String {
        let value = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return "\(value.formatted(.number.precision(.fractionLength(1)))) s"
    }

    static func path(_ finding: Finding) -> String {
        guard case .file(let ref) = finding.subject else { return finding.id }
        return abbreviated(ref.path)
    }

    static func name(_ finding: Finding) -> String {
        guard case .file(let ref) = finding.subject else { return finding.id }
        return Paths.lastComponent(ref.path)
    }

    static func owner(_ finding: Finding) -> String? {
        for evidence in finding.evidence {
            switch evidence {
            case .owner(let name, _): return name
            case .ownerNotInstalled(let bundleID): return "\(bundleID) (no installed app)"
            default: continue
            }
        }
        return nil
    }

    static func describe(_ owner: Owner) -> String {
        switch owner.status {
        case .installed: "\(owner.name) (installed app)"
        case .system: "macOS"
        case .notInstalled: "No installed app uses the name \(owner.name). It may be left over from an app you removed."
        case .unknown: "Not named after an app"
        }
    }

    static func describe(_ verdict: SafetyPolicy.Verdict) -> String {
        switch verdict {
        case .allowed: "Cleanup rules may target it"
        case .selectionOnly(let reason): "Only removable if you choose it yourself (\(reason.rawValue))"
        case .denied(let reason): "Never removable (\(reason.rawValue))"
        }
    }

    static func absolute(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let joined = expanded.hasPrefix("/") ? expanded : Paths.join(FileManager.default.currentDirectoryPath, expanded)
        return PathCanonicalizer.canonicalize(joined) ?? joined
    }

    static func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path == home || path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

private struct JunkJSON: Encodable {
    struct Group: Encodable {
        let rule: String
        let title: String
        let safety: String
        let explanation: String
        let ifRemoved: String
        let allocatedBytes: UInt64
        let reclaimableBytes: UInt64
        let items: [Item]
    }

    struct Item: Encodable {
        let path: String
        let allocatedBytes: UInt64
        let reclaimableBytes: UInt64?
        let owner: String?
        let mustQuit: [String]
    }

    let packVersion: String
    let groups: [Group]
    let unreadable: [String]

    init(report: RuleScanReport) {
        packVersion = report.packVersion
        unreadable = report.unreadable.map(\.path)
        groups = report.groups.map { group in
            Group(
                rule: group.rule.id,
                title: group.rule.title,
                safety: group.rule.safety.rawValue,
                explanation: group.rule.explanation,
                ifRemoved: group.rule.ifRemoved,
                allocatedBytes: group.allocatedBytes,
                reclaimableBytes: group.reclaimableBytes,
                items: group.findings.map { finding in
                    Item(
                        path: Text.path(finding),
                        allocatedBytes: finding.size.allocated,
                        reclaimableBytes: finding.size.reclaimable,
                        owner: Text.owner(finding),
                        mustQuit: finding.constraints.compactMap {
                            if case .requiresQuit(let bundleID) = $0 { return bundleID }
                            return nil
                        }
                    )
                }
            )
        }
    }
}
