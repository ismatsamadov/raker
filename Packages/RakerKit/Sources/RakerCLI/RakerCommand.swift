import ArgumentParser
import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import SafetyPolicy
import ScanEngine
import SpaceIndex

@main
struct RakerCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "raker",
        abstract: "Find what uses storage on your Mac.",
        discussion: "Developer harness for the Raker engines. Only `clean --execute` removes anything.",
        subcommands: [
            DiskUsage.self, Largest.self, Downloads.self, Large.self, Junk.self, Explain.self, Clean.self,
            History.self, Restore.self, Volume.self, Check.self,
        ]
    )
}

// MARK: - du

struct DiskUsage: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "du",
        abstract: "Show the largest items under a folder, as a tree."
    )

    @Argument(help: "Folder to scan.")
    var path = "."

    @Option(name: .shortAndLong, help: "How many levels to show.")
    var depth = 1

    @Option(name: .shortAndLong, help: "Items to show per folder.")
    var top = 12

    @Flag(help: "Descend into other volumes mounted inside the folder.")
    var crossMounts = false

    @Flag(help: "List every location that couldn't be read.")
    var showSkipped = false

    @Flag(help: "Print JSON instead of text.")
    var json = false

    func run() async throws {
        let report = try await Scanning.run(ScanScope(path: path, crossesMountPoints: crossMounts), quiet: json)
        let tree = report.tree
        if json {
            try Output.printJSON(DiskUsageJSON(tree: tree, depth: depth, top: top, report: report))
            return
        }
        print(Output.row(tree.path(of: tree.root), size: tree.allocatedSize(of: tree.root),
                         detail: "\(tree.descendantCount(of: tree.root).formatted()) items"))
        printChildren(of: tree.root, in: tree, prefix: "", level: 1)
        Output.printSummary(report, showSkipped: showSkipped)
    }

    private func printChildren(of index: SizeTree.Index, in tree: SizeTree, prefix: String, level: Int) {
        guard level <= depth else { return }
        let children = tree.largestChildren(of: index)
        let shown = children.prefix(top)
        for (position, child) in shown.enumerated() {
            let isLast = position == shown.count - 1 && children.count <= top
            let branch = isLast ? "└─ " : "├─ "
            let isFolder = tree.kind(of: child) == .directory
            let detail = isFolder ? "\(tree.descendantCount(of: child).formatted()) items" : ""
            let name = tree.name(of: child) + (isFolder ? "/" : "")
            print(Output.row(prefix + branch + name, size: tree.allocatedSize(of: child), detail: detail))
            if isFolder {
                printChildren(of: child, in: tree, prefix: prefix + (isLast ? "   " : "│  "), level: level + 1)
            }
        }
        if children.count > top {
            let rest = children.dropFirst(top).reduce(UInt64(0)) { $0 + tree.allocatedSize(of: $1) }
            print(Output.row(prefix + "└─ \(children.count - top) more", size: rest, detail: ""))
        }
    }
}

// MARK: - largest

struct Largest: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the largest files under a folder.")

    @Argument(help: "Folder to scan.")
    var path = "."

    @Option(name: .shortAndLong, help: "How many files to list.")
    var count = 20

    @Flag(help: "Print JSON instead of text.")
    var json = false

    func run() async throws {
        let report = try await Scanning.run(ScanScope(path: path), quiet: json)
        let tree = report.tree
        let files = tree.largestFiles(limit: count)
        if json {
            try Output.printJSON(files.map { FileJSON(tree: tree, index: $0) })
            return
        }
        for index in files {
            let modified = tree.modificationDate(of: index).formatted(date: .abbreviated, time: .omitted)
            print(Output.row(tree.path(of: index), size: tree.allocatedSize(of: index), detail: modified))
        }
        Output.printSummary(report, showSkipped: false)
    }
}

// MARK: - volume

struct Volume: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show capacity of the volume that holds a path.")

    @Argument(help: "Any path on the volume.")
    var path = "/"

    func run() throws {
        let space = try VolumeInfo.space(containing: path)
        let name = VolumeInfo.name(containing: path) ?? path
        print(name)
        print(Output.row("  Capacity", size: space.total, detail: ""))
        print(Output.row("  Used", size: space.used, detail: ""))
        print(Output.row("  Free", size: space.free, detail: ""))
        print(Output.row("  Available, including purgeable", size: space.availableIncludingPurgeable, detail: ""))
        print(Output.row("  Purgeable (estimate)", size: space.purgeableEstimate, detail: ""))
    }
}

// MARK: - check

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show what the safety policy says about paths. Nothing is removed."
    )

    @Argument(help: "Paths to evaluate.")
    var paths: [String]

    func run() {
        let policy = SafetyPolicy(homeDirectory: NSHomeDirectory())
        for path in paths {
            let absolute = path.hasPrefix("/") ? path : Paths.join(FileManager.default.currentDirectoryPath, path)
            let verdict: String
            switch policy.evaluate(absolute) {
            case .allowed: verdict = "allowed (rules may target it)"
            case .selectionOnly(let reason): verdict = "only by explicit selection (\(reason.rawValue))"
            case .denied(let reason): verdict = "never removable (\(reason.rawValue))"
            }
            print("\(absolute): \(verdict)")
        }
    }
}

// MARK: - Shared helpers

enum Scanning {
    static func run(_ scope: ScanScope, quiet: Bool) async throws -> ScanReport {
        let showProgress = !quiet && isatty(STDERR_FILENO) == 1
        do {
            let report = try await ScanEngine().scan(scope) { progress in
                guard showProgress else { return }
                let line = "Scanning… \(progress.counters.items.formatted()) items, "
                    + ByteCount(progress.counters.allocatedBytes).formatted
                FileHandle.standardError.write(Data(("\r\u{1B}[2K" + line).utf8))
            }
            if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
            return report
        } catch {
            if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }
            throw ValidationError(Output.describe(error))
        }
    }
}

enum Output {
    static func row(_ label: String, size: UInt64, detail: String) -> String {
        let sizeText = ByteCount(size).formatted
        let padded = label.count < 60 ? label + String(repeating: " ", count: 60 - label.count) : label
        let sizeColumn = String(repeating: " ", count: max(0, 10 - sizeText.count)) + sizeText
        return detail.isEmpty ? "\(padded) \(sizeColumn)" : "\(padded) \(sizeColumn)   \(detail)"
    }

    static func printSummary(_ report: ScanReport, showSkipped: Bool) {
        let seconds = Double(report.duration.components.seconds)
            + Double(report.duration.components.attoseconds) / 1e18
        var line = "\nScanned \(report.tree.count.formatted()) items in \(seconds.formatted(.number.precision(.fractionLength(2)))) s"
        if !report.completed { line += " (cancelled, partial results)" }
        if !report.skipped.isEmpty {
            line += ". \(report.skipped.count) location(s) couldn't be read"
            if !showSkipped { line += " (--show-skipped lists them)" }
        }
        print(line + ".")
        guard showSkipped else { return }
        for location in report.skipped {
            print("  skipped \(location.path): \(describe(location.reason))")
        }
    }

    static func describe(_ reason: SkippedLocation.Reason) -> String {
        switch reason {
        case .permissionDenied(let area):
            switch area {
            case .rootOnly: return "readable only by root"
            case .desktop, .documents, .downloads: return "needs access to the \(area.rawValue.capitalized) folder"
            case .removableVolumes, .networkVolumes: return "needs access to the volume"
            default: return "needs Full Disk Access (\(area.rawValue))"
            }
        case .notFound: return "disappeared during the scan"
        case .ioError(let code): return "I/O error \(code)"
        }
    }

    static func describe(_ error: any Error) -> String {
        switch error as? ScanError {
        case .rootNotFound(let path): return "No such folder: \(path)"
        case .rootNotDirectory(let path): return "Not a folder: \(path)"
        case .rootUnreadable(let path, let code): return "Can't read \(path) (\(code))"
        case nil: return error.localizedDescription
        }
    }

    static func printJSON(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}

struct FileJSON: Encodable {
    let path: String
    let allocatedBytes: UInt64
    let logicalBytes: UInt64
    let reclaimableBytes: UInt64?
    let modified: Date

    init(tree: SizeTree, index: SizeTree.Index) {
        let size = tree.size(of: index)
        path = tree.path(of: index)
        allocatedBytes = size.allocated
        logicalBytes = size.logical
        reclaimableBytes = size.reclaimable
        modified = tree.modificationDate(of: index)
    }
}

struct DiskUsageJSON: Encodable {
    struct Node: Encodable {
        let name: String
        let kind: String
        let allocatedBytes: UInt64
        let reclaimableBytes: UInt64?
        let items: Int
        let children: [Node]?
    }

    let root: Node
    let durationSeconds: Double
    let completed: Bool
    let skipped: [String]

    init(tree: SizeTree, depth: Int, top: Int, report: ScanReport) {
        func node(_ index: SizeTree.Index, level: Int) -> Node {
            let isFolder = tree.kind(of: index) == .directory
            let children = isFolder && level < depth
                ? tree.largestChildren(of: index, limit: top).map { node($0, level: level + 1) }
                : nil
            return Node(
                name: index == tree.root ? tree.rootPath : tree.name(of: index),
                kind: isFolder ? "folder" : "file",
                allocatedBytes: tree.allocatedSize(of: index),
                reclaimableBytes: tree.size(of: index).reclaimable,
                items: tree.descendantCount(of: index),
                children: children
            )
        }
        root = node(tree.root, level: 0)
        durationSeconds = Double(report.duration.components.seconds)
            + Double(report.duration.components.attoseconds) / 1e18
        completed = report.completed
        skipped = report.skipped.map(\.path)
    }
}
