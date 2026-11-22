import ArgumentParser
import Foundation
import Persistence
import RakerModel

struct Exclude: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tell Raker never to suggest or remove anything at or inside a path.",
        discussion: "With --lock, the path is a locked original instead: always the copy that stays when it has duplicates."
    )

    @Argument(help: "The file or folder.")
    var path: String

    @Flag(help: "Lock it as an original instead of excluding it.")
    var lock = false

    func run() throws {
        let absolute = Text.absolute(path)
        try AppDatabase.open().userRules.add(UserRule(path: absolute, kind: lock ? .lockOriginal : .exclude))
        print(lock ? "Locked \(Text.abbreviated(absolute)) as an original." : "Raker will leave \(Text.abbreviated(absolute)) alone.")
    }
}

struct Exclusions: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List exclusions and locked originals.")

    @Option(help: "Remove the rules for this path.")
    var remove: String?

    func run() throws {
        let store = try AppDatabase.open().userRules
        if let remove {
            let absolute = Text.absolute(remove)
            let matches = try store.all().filter { $0.path == absolute }
            guard !matches.isEmpty else { throw ValidationError("No rule for \(Text.abbreviated(absolute)).") }
            for rule in matches { try store.remove(id: rule.id) }
            print("Removed \(matches.count) rule\(matches.count == 1 ? "" : "s") for \(Text.abbreviated(absolute)).")
            return
        }
        let rules = try store.all()
        guard !rules.isEmpty else {
            print("No exclusions or locked originals.")
            return
        }
        for rule in rules {
            print("\(rule.kind == .exclude ? "never suggested" : "locked original")  \(Text.abbreviated(rule.path))")
        }
    }
}

/// The user's rules, as stored by the app and these commands.
enum StoredRules {
    static func load() -> [UserRule] {
        (try? AppDatabase.open().userRules.all()) ?? []
    }
}
