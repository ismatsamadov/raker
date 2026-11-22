import Foundation
import RakerModel
import RuleEngine
import Testing
@testable import ScanEngine

private struct FakeApps: AppDirectory {
    var installed: [String: String] = [:]
    var running: Set<String> = []

    func installedApp(bundleID: String) -> InstalledApp? {
        installed[bundleID].map { InstalledApp(bundleID: bundleID, name: $0, path: "/Applications/\($0).app") }
    }

    func isRunning(bundleID: String) -> Bool {
        running.contains(bundleID)
    }
}

/// A fake home folder and per-user temporary area with known contents.
private struct Home {
    let fixture: Fixture
    let environment: PathEnvironment

    init() throws {
        fixture = try Fixture()
        environment = PathEnvironment(
            home: fixture.path + "/home",
            userRoot: fixture.path,
            userDirectory: fixture.path + "/0",
            userTemporary: fixture.path + "/T",
            userCache: fixture.path + "/C"
        )
        try fixture.file("home/Library/Caches/com.example.App/data.bin", bytes: 50_000)
        try fixture.file("home/Library/Caches/com.gone.Editor/old.bin", bytes: 20_000)
        try fixture.file("home/Library/Caches/go-build/aa/object.bin", bytes: 30_000)
        try fixture.file("home/Library/Caches/Google/Chrome/Default/cache.bin", bytes: 40_000)
        try fixture.file("home/Library/Caches/Google/Other/other.bin", bytes: 10_000)
        try fixture.file("home/Library/Logs/DiagnosticReports/recent.ips", bytes: 5_000)
        try fixture.file("home/Library/Keychains/login.keychain-db", bytes: 8_000)
        try fixture.file("home/Documents/report.pdf", bytes: 9_000)
        try fixture.file("T/old-download.tmp", bytes: 7_000)
        try fixture.file("T/in-use.tmp", bytes: 6_000)
        let tenDaysAgo = Date(timeIntervalSinceNow: -10 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: tenDaysAgo], ofItemAtPath: fixture.path + "/T/old-download.tmp")
    }

    func path(_ relative: String) -> String { fixture.path + "/" + relative }
}

private let pack = RulePack(version: "test", rules: [
    Rule(id: "chrome", title: "Chrome cache", explanation: "e", ifRemoved: "i", category: "caches.browsers",
         safety: .regenerable, targets: [RuleTarget(path: "~/Library/Caches/Google/Chrome", scope: .contents)],
         appBundleIDs: ["com.google.Chrome"], whileRunning: .requireQuit),
    Rule(id: "go", title: "Go build cache", explanation: "e", ifRemoved: "i", category: "developer.caches",
         safety: .regenerable, targets: [RuleTarget(path: "~/Library/Caches/go-build", scope: .contents)]),
    Rule(id: "temp", title: "Temporary files", explanation: "e", ifRemoved: "i", category: "temporary",
         safety: .regenerable, targets: [RuleTarget(path: "$DARWIN_USER_TEMP_DIR", scope: .contents, olderThanDays: 3)]),
    Rule(id: "crash", title: "Old crash reports", explanation: "e", ifRemoved: "i", category: "logs",
         safety: .regenerable, targets: [RuleTarget(path: "~/Library/Logs/DiagnosticReports", scope: .contents, olderThanDays: 30)]),
    Rule(id: "caches", title: "App caches", explanation: "e", ifRemoved: "i", category: "caches.apps",
         safety: .regenerable, targets: [RuleTarget(path: "~/Library/Caches/*", scope: .item)],
         whileRunning: .requireQuit, identifiesOwners: true),
    // Too broad on purpose: validation can't see every match, so the scanner must refuse
    // protected children such as Keychains at run time.
    Rule(id: "too-broad", title: "Everything in Library", explanation: "e", ifRemoved: "i", category: "test",
         safety: .regenerable, targets: [RuleTarget(path: "~/Library/*", scope: .item)]),
])

@Suite("RuleScanner")
struct RuleScannerTests {
    @Test("Produces explained findings, and specific rules win over generic ones")
    func findings() async throws {
        let home = try Home()
        defer { home.fixture.remove() }
        let apps = FakeApps(installed: ["com.example.App": "Example"], running: ["com.example.App"])

        let report = await RuleScanner(pack: pack, environment: home.environment, apps: apps).scan()
        let paths = Dictionary(grouping: report.findings) { $0.id.split(separator: ":").first.map(String.init) ?? "" }
            .mapValues { $0.compactMap { finding -> String? in
                if case .file(let ref) = finding.subject { return ref.path }
                return nil
            }.sorted() }

        #expect(paths["chrome"] == [home.path("home/Library/Caches/Google/Chrome/Default")])
        #expect(paths["go"] == [home.path("home/Library/Caches/go-build/aa")])
        #expect(paths["caches"] == [
            home.path("home/Library/Caches/Google/Other"),
            home.path("home/Library/Caches/com.example.App"),
            home.path("home/Library/Caches/com.gone.Editor"),
        ].sorted())
        #expect(paths["temp"] == [home.path("T/old-download.tmp")])
        #expect(paths["crash"] == nil)
        #expect(paths["too-broad"] == nil)
    }

    @Test("Never lists protected or personal files, even for an overly broad rule")
    func safety() async throws {
        let home = try Home()
        defer { home.fixture.remove() }

        let report = await RuleScanner(pack: pack, environment: home.environment, apps: FakeApps()).scan()
        let paths = report.findings.compactMap { finding -> String? in
            if case .file(let ref) = finding.subject { return ref.path }
            return nil
        }

        #expect(!paths.contains { $0.contains("/Keychains") })
        #expect(!paths.contains { $0.contains("/Documents") })
        #expect(!paths.contains(home.path("home/Library/Caches")))
        #expect(!paths.contains(home.path("home/Library/Logs")))
    }

    @Test("Labels owners, flags missing apps, and asks to quit running ones")
    func owners() async throws {
        let home = try Home()
        defer { home.fixture.remove() }
        let apps = FakeApps(installed: ["com.example.App": "Example"], running: ["com.example.App"])

        let report = await RuleScanner(pack: pack, environment: home.environment, apps: apps).scan()
        let example = try #require(report.findings.first { $0.id.hasSuffix("/com.example.App") })
        let gone = try #require(report.findings.first { $0.id.hasSuffix("/com.gone.Editor") })

        #expect(example.evidence.contains(.owner(name: "Example", bundleID: "com.example.App")))
        #expect(example.constraints == [.requiresQuit(bundleID: "com.example.App")])
        #expect(gone.evidence.contains(.ownerNotInstalled(bundleID: "com.gone.Editor")))
        #expect(gone.constraints.isEmpty)
    }

    @Test("Reports locations it wasn't allowed to read instead of leaving them out silently")
    func unreadable() async throws {
        let home = try Home()
        defer { home.fixture.remove() }
        try home.fixture.file("home/Library/Caches/com.locked.App/data.bin", bytes: 10_000)
        try home.fixture.file("home/Library/Logs/Locked/old.log", bytes: 10_000)
        // Refused the way macOS's privacy protection refuses a folder.
        chmod(home.path("home/Library/Caches/com.locked.App"), 0)
        chmod(home.path("home/Library/Logs/Locked"), 0)
        let lockedPack = RulePack(version: "test", rules: [
            Rule(id: "logs", title: "Logs", explanation: "e", ifRemoved: "i", category: "logs",
                 safety: .regenerable, targets: [RuleTarget(path: "~/Library/Logs/Locked", scope: .contents)]),
            Rule(id: "caches", title: "App caches", explanation: "e", ifRemoved: "i", category: "caches.apps",
                 safety: .regenerable, targets: [RuleTarget(path: "~/Library/Caches/*", scope: .item)]),
        ])

        let report = await RuleScanner(pack: lockedPack, environment: home.environment, apps: FakeApps()).scan()

        #expect(report.unreadable.map(\.path) == [
            home.path("home/Library/Caches/com.locked.App"),
            home.path("home/Library/Logs/Locked"),
        ])
        #expect(report.unreadable.allSatisfy { $0.reason == .permissionDenied(area: .fullDiskAccess) })
        #expect(!report.findings.contains { $0.id.hasSuffix("/com.locked.App") })
        #expect(report.findings.contains { $0.id.hasSuffix("/com.example.App") })
        #expect(report.filtered { _ in false }.unreadable == report.unreadable)
    }

    @Test("Sizes, safety levels and preselection come from the rules")
    func sizesAndSafety() async throws {
        let home = try Home()
        defer { home.fixture.remove() }

        let report = await RuleScanner(pack: pack, environment: home.environment, apps: FakeApps()).scan()

        #expect(report.findings.allSatisfy { $0.size.allocated > 0 && $0.safety == .regenerable && $0.preselected })
        let go = try #require(report.groups.first { $0.rule.id == "go" })
        #expect(go.findings.first?.size.logical == 30_000)
        #expect(report.allocatedBytes(safety: .regenerable) == report.groups.reduce(0) { $0 + $1.allocatedBytes })
        #expect(report.allocatedBytes(safety: .review) == 0)
    }
}

@Suite("LocationExplainer")
struct LocationExplainerTests {
    @Test("Explains covered items, known locations and protected paths")
    func explain() throws {
        let home = try Home()
        defer { home.fixture.remove() }
        let explainPack = RulePack(version: "test", rules: pack.rules, locations: [
            KnownLocation(path: "~/Library/Caches", title: "App caches", explanation: "e", removable: false),
            KnownLocation(path: "~/Library/Keychains", title: "Keychains", explanation: "Passwords.", removable: false),
        ])
        let explainer = LocationExplainer(pack: explainPack, environment: home.environment, apps: FakeApps())

        let cache = explainer.explain(home.path("home/Library/Caches/go-build/aa"))
        #expect(cache.rule?.id == "go")
        #expect(cache.knownLocation?.title == "App caches")
        #expect(!cache.knownLocationIsExact)
        #expect(cache.measurement?.size.logical == 30_000)

        // A folder whose contents a rule removes is explained by that rule, not the generic one.
        let folder = explainer.explain(home.path("home/Library/Caches/go-build"))
        #expect(folder.rule?.id == "go")

        let keychains = explainer.explain(home.path("home/Library/Keychains"))
        #expect(keychains.knownLocationIsExact)
        #expect(keychains.verdict == .denied(.credentials))

        // Without measuring, the answer is the same, just without sizes.
        let quick = explainer.explain(home.path("home/Library/Caches/go-build/aa"), measuring: false)
        #expect(quick.rule?.id == "go")
        #expect(quick.measurement == nil)
    }
}
