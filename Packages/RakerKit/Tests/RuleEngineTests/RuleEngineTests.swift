import Foundation
import RakerModel
import Testing
@testable import RuleEngine

struct FakeApps: AppDirectory {
    var installed: [String: String] = [:]
    var running: Set<String> = []

    func installedApp(bundleID: String) -> InstalledApp? {
        installed[bundleID].map { InstalledApp(bundleID: bundleID, name: $0, path: "/Applications/\($0).app") }
    }

    func isRunning(bundleID: String) -> Bool {
        running.contains(bundleID)
    }
}

private let testEnvironment = PathEnvironment(
    home: "/Users/alex",
    userRoot: "/private/var/folders/ab/cd",
    userDirectory: "/private/var/folders/ab/cd/0",
    userTemporary: "/private/var/folders/ab/cd/T",
    userCache: "/private/var/folders/ab/cd/C"
)

private func rule(_ id: String, _ path: String, scope: TargetScope = .item) -> Rule {
    Rule(id: id, title: id, explanation: "x", ifRemoved: "y", category: "test", safety: .regenerable,
         targets: [RuleTarget(path: path, scope: scope)])
}

@Suite("Rule packs")
struct RulePackTests {
    @Test("Duplicate rule IDs are rejected")
    func duplicateIDs() {
        let pack = RulePack(version: "t", rules: [rule("a", "~/Library/Caches/x"), rule("a", "~/Library/Caches/y")])
        #expect(throws: RulePackError.duplicateRuleID("a")) {
            try RulePackLoader.validate(pack, environment: testEnvironment)
        }
    }

    @Test("Rules that could reach protected locations are rejected", arguments: [
        ("~/Documents/*", TargetScope.item, "personalFiles"),
        ("~/Desktop", TargetScope.contents, "personalFiles"),
        ("/System/Library/Caches/*", TargetScope.item, "systemLocation"),
        ("~/.ssh", TargetScope.contents, "credentials"),
        ("~/Library/Keychains", TargetScope.contents, "credentials"),
        ("~/Library/Caches", TargetScope.item, "protectedFolder"),
    ])
    func unsafeTargets(path: String, scope: TargetScope, reason: String) {
        let pack = RulePack(version: "t", rules: [rule("bad", path, scope: scope)])
        #expect(throws: RulePackError.unsafeTarget(rule: "bad", path: path, reason: reason)) {
            try RulePackLoader.validate(pack, environment: testEnvironment)
        }
    }

    @Test("Unknown variables are rejected")
    func unknownVariables() {
        let pack = RulePack(version: "t", rules: [rule("v", "$NOT_A_VARIABLE/cache")])
        #expect(throws: RulePackError.unknownVariable(rule: "v", path: "$NOT_A_VARIABLE/cache")) {
            try RulePackLoader.validate(pack, environment: testEnvironment)
        }
    }

    @Test("Disabled rules are skipped")
    func disabledRules() {
        let pack = RulePack(version: "t", rules: [rule("on", "~/a"), rule("off", "~/b")], disabledRules: ["off"])
        #expect(pack.activeRules.map(\.id) == ["on"])
    }

    @Test("Packs decode from JSON with defaults for optional fields")
    func decoding() throws {
        let json = """
        {"schema": 1, "version": "v", "rules": [{"id": "r", "title": "T", "explanation": "E", "ifRemoved": "I",
         "category": "c", "safety": "review", "targets": [{"path": "~/Library/Caches/x", "scope": "contents"}]}]}
        """
        let pack = try RulePackLoader.decode(Data(json.utf8))
        let decoded = try #require(pack.rules.first)
        #expect(decoded.safety == .review)
        #expect(decoded.whileRunning == .allow)
        #expect(decoded.targets.first?.scope == .contents)
        #expect(pack.locations.isEmpty)
        #expect(throws: RulePackError.unsupportedSchema(9)) {
            try RulePackLoader.decode(Data(#"{"schema": 9, "version": "v", "rules": []}"#.utf8))
        }
    }
}

@Suite("Path patterns")
struct PathPatternTests {
    @Test("Expands the home folder and per-user variables")
    func expansion() {
        #expect(PathPattern.expand("~/Library/Caches", in: testEnvironment) == "/Users/alex/Library/Caches")
        #expect(PathPattern.expand("~", in: testEnvironment) == "/Users/alex")
        #expect(PathPattern.expand("$DARWIN_USER_TEMP_DIR/x", in: testEnvironment) == "/private/var/folders/ab/cd/T/x")
        #expect(PathPattern.expand("$DARWIN_USER_ROOT/X", in: testEnvironment) == "/private/var/folders/ab/cd/X")
        #expect(PathPattern.expand("$DARWIN_USER_DIR", in: testEnvironment) == "/private/var/folders/ab/cd/0")
        #expect(PathPattern.expand("$NOPE/x", in: testEnvironment) == nil)
        #expect(PathPattern.expand("relative/x", in: testEnvironment) == nil)
    }

    @Test("Wildcards match within one component, ignoring case")
    func wildcardMatching() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("raker-pattern-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["com.apple.one", "com.Apple.two", "org.example", "nested/com.apple.deep"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let base = root.resolvingSymlinksInPath().path
        let matches = PathPattern.existingMatches(of: base + "/com.apple.*").map { ($0 as NSString).lastPathComponent }
        #expect(matches.sorted() == ["com.Apple.two", "com.apple.one"])
        #expect(PathPattern.existingMatches(of: base + "/missing/*").isEmpty)
    }

    @Test("Covers the matched item and everything inside it")
    func covers() {
        #expect(PathPattern.covers("/Users/alex/Library/Caches/*", path: "/Users/alex/Library/Caches/com.x/y"))
        #expect(PathPattern.covers("/Users/alex/Library/Caches/*", path: "/Users/alex/library/caches/Z"))
        #expect(!PathPattern.covers("/Users/alex/Library/Caches/*", path: "/Users/alex/Library/Caches"))
        #expect(!PathPattern.covers("/Users/alex/Library/Caches/*", path: "/Users/alex/Library/Logs/x"))
    }
}

@Suite("Owner resolution")
struct OwnerResolverTests {
    let resolver = OwnerResolver(apps: FakeApps(installed: ["com.example.App": "Example", "com.apple.Safari": "Safari"]))

    @Test("Folders named after installed apps, or their helpers, resolve to the app")
    func installedApps() {
        #expect(resolver.owner(ofFolderNamed: "com.example.App") == Owner(name: "Example", bundleID: "com.example.App", status: .installed))
        #expect(resolver.owner(ofFolderNamed: "com.example.App.ShipIt").name == "Example")
        #expect(resolver.owner(ofFolderNamed: "com.apple.Safari").status == .installed)
    }

    @Test("Apple service folders belong to macOS")
    func systemFolders() {
        #expect(resolver.owner(ofFolderNamed: "com.apple.nsurlsessiond").status == .system)
    }

    @Test("App-style names without an installed app are flagged, not assumed safe")
    func notInstalled() {
        #expect(resolver.owner(ofFolderNamed: "com.gone.Editor") == Owner(name: "com.gone.Editor", bundleID: "com.gone.Editor", status: .notInstalled))
    }

    @Test("Other names are reported as they are")
    func plainNames() {
        #expect(resolver.owner(ofFolderNamed: "go-build").status == .unknown)
        #expect(resolver.owner(ofFolderNamed: "Google").status == .unknown)
        #expect(resolver.owner(ofFolderNamed: "v1.2.3").status == .unknown)
    }
}
