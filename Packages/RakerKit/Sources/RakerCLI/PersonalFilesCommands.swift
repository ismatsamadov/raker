import ArgumentParser
import Foundation
import RakerFoundation
import RakerModel
import ScanEngine
import SystemKit

// MARK: - downloads

struct Downloads: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List what's in Downloads: where each item came from and whether its app is installed.",
        discussion: "Read-only."
    )

    @Option(help: "Look at this folder instead of Downloads.")
    var folder: String?

    func run() async throws {
        let path = folder ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "~/Downloads"
        let report = try await Scanning.run(ScanScope(path: path), quiet: false)
        let findings = PersonalFiles.finder().downloads(in: report.tree)
        guard !findings.isEmpty else {
            print("Nothing in \(Text.abbreviated(report.tree.rootPath)).")
            return
        }
        PersonalFiles.print(findings)
        let installers = findings.filter { $0.installedApp != nil }
        if !installers.isEmpty {
            let bytes = installers.reduce(UInt64(0)) { $0 &+ $1.size.allocated }
            print("\n\(installers.count) installer\(installers.count == 1 ? " is" : "s are") for apps you already have (\(ByteCount(bytes).formatted)).")
        }
    }
}

// MARK: - large

struct Large: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List large files, optionally only ones you haven't opened for a while.",
        discussion: "App bundles, ~/Library and hidden folders are left out. Read-only."
    )

    @Argument(help: "Folder to scan.")
    var path = "~"

    @Option(help: "Smallest size to list, in megabytes.")
    var minimumMB: UInt64 = 50

    @Option(help: "Only files not opened for this many days.")
    var notOpenedDays: Int?

    func run() async throws {
        let report = try await Scanning.run(ScanScope(path: path), quiet: false)
        let criteria = PersonalFileFinder.LargeFileCriteria(minimumSize: minimumMB * 1_000_000, notOpenedForDays: notOpenedDays)
        let findings = PersonalFiles.finder().largeFiles(in: report.tree, criteria: criteria)
        guard !findings.isEmpty else {
            print("No files match.")
            return
        }
        PersonalFiles.print(findings)
    }
}

// MARK: - Helpers

private enum PersonalFiles {
    static func finder() -> PersonalFileFinder {
        let rules = StoredRules.load()
        return PersonalFileFinder(metadata: SystemFileMetadata(), installedAppNames: ApplicationsFolder.installedAppNames(),
                                  exclusions: rules.exclusions, lockedOriginals: rules.lockedOriginals)
    }

    static func print(_ findings: [Finding]) {
        for finding in findings {
            var details: [String] = []
            if let app = finding.installedApp { details.append("\(app) is installed") }
            if let site = finding.site { details.append("from \(site)") }
            if let opened = finding.opened {
                details.append("opened \(opened.formatted(.relative(presentation: .named)))")
            }
            if finding.constraints.contains(where: { if case .synced = $0 { true } else { false } }) {
                details.append("synced")
            }
            guard case .file(let ref) = finding.subject else { continue }
            Swift.print(Output.row(Text.abbreviated(ref.path), size: finding.size.allocated, detail: details.joined(separator: ", ")))
        }
    }
}

private extension Finding {
    var installedApp: String? {
        evidence.lazy.compactMap { if case .appInstalled(let name) = $0 { name } else { nil } }.first
    }

    var site: String? {
        evidence.lazy.compactMap { if case .downloadedFrom(let site) = $0 { site } else { nil } }.first
    }

    var opened: Date? {
        evidence.lazy.compactMap { if case .lastOpened(let date) = $0 { date } else { nil } }.first
    }
}
