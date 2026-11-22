import ArgumentParser
import DuplicateEngine
import Foundation
import RakerFoundation
import ScanEngine

struct Dupes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Find files with identical content. ★ marks the copy Raker suggests keeping.",
        discussion: "Reads file contents on this Mac to compare them. Read-only."
    )

    @Argument(help: "Folder to search.")
    var path = "~"

    @Option(help: "Smallest file size to compare, in kilobytes.")
    var minimumKB: UInt64 = 100

    @Option(help: "Which copy to suggest keeping: original, oldest, newest or shortestPath.")
    var keep: String = SurvivorStrategy.original.rawValue

    func run() async throws {
        guard let strategy = SurvivorStrategy(rawValue: keep) else {
            throw ValidationError("--keep must be one of: \(SurvivorStrategy.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        let report = try await Scanning.run(ScanScope(path: path), quiet: false)
        let showProgress = isatty(STDERR_FILENO) == 1
        let finder = DuplicateFinder(options: .init(minimumSize: minimumKB * 1_000))
        let sets = await finder.find(in: report.tree) { progress in
            guard showProgress, progress.filesToHash > 0 else { return }
            let line = "Comparing \(progress.filesHashed.formatted()) of \(progress.filesToHash.formatted()) files…"
            FileHandle.standardError.write(Data(("\r\u{1B}[2K" + line).utf8))
        }
        if showProgress { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) }

        guard !sets.isEmpty else {
            print("No duplicates found.")
            return
        }
        var total: UInt64 = 0
        for set in sets {
            let keeper = strategy.keeper(in: set)
            let frees = set.reclaimable(keeping: keeper.path)
            total &+= frees
            let note = set.sharesAllData ? "copies share their data, frees nothing" : "frees \(ByteCount(frees).formatted)"
            print("\n\(set.files.count) copies of \(ByteCount(set.size).formatted), \(note)")
            for file in set.files {
                print("  \(file.path == keeper.path ? "★" : " ") \(Text.abbreviated(file.path))")
            }
        }
        print("\n\(sets.count) set\(sets.count == 1 ? "" : "s"); removing the extra copies would free \(ByteCount(total).formatted). Nothing was changed.")
    }
}
