import Foundation
import RakerModel
import Testing
@testable import ScanEngine

private struct FakeMetadata: FileMetadataSource {
    var opened: [String: Date] = [:]
    var sources: [String: DownloadSource] = [:]

    func lastOpened(_ path: String) -> Date? {
        opened.first { path.hasSuffix($0.key) }?.value
    }

    func downloadSource(_ path: String) -> DownloadSource? {
        sources.first { path.hasSuffix($0.key) }?.value
    }
}

@Suite("PersonalFileFinder")
struct PersonalFileFinderTests {
    @Test("Lists what's in Downloads with its origin, and matches installers to installed apps")
    func downloads() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Downloads/Docker.dmg", bytes: 60_000)
        try fixture.file("Downloads/Figma-125.0.dmg", bytes: 40_000)
        try fixture.file("Downloads/Archive-2019.zip", bytes: 30_000)
        try fixture.file("Downloads/notes.txt", bytes: 1_000)
        try fixture.file("Downloads/.DS_Store", bytes: 6_000)
        try fixture.file("Downloads/Example.app/Contents/MacOS/Example", bytes: 20_000)
        let metadata = FakeMetadata(
            opened: ["notes.txt": Date(timeIntervalSince1970: 1_700_000_000)],
            sources: ["Docker.dmg": DownloadSource(
                urls: ["https://desktop.docker.com/mac/Docker.dmg", "https://www.docker.com/products/docker-desktop/"],
                agent: "Safari", downloadedAt: nil
            )]
        )
        let finder = PersonalFileFinder(metadata: metadata, installedAppNames: ["Docker", "Figma", "Arc", "Example"],
                                        homeDirectory: fixture.path)

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path + "/Downloads")).tree
        let findings = finder.downloads(in: tree)
        let byName = Dictionary(uniqueKeysWithValues: findings.map { (($0.id as NSString).lastPathComponent, $0) })

        #expect(byName.keys.sorted() == ["Archive-2019.zip", "Docker.dmg", "Example.app", "Figma-125.0.dmg", "notes.txt"])
        #expect(byName["Docker.dmg"]?.evidence.contains(.appInstalled(name: "Docker")) == true)
        #expect(byName["Docker.dmg"]?.evidence.contains(.downloadedFrom("docker.com")) == true)
        #expect(byName["Figma-125.0.dmg"]?.evidence.contains(.appInstalled(name: "Figma")) == true)
        #expect(byName["Archive-2019.zip"]?.evidence.contains { if case .appInstalled = $0 { true } else { false } } == false)
        #expect(byName["Example.app"]?.category == "downloads.apps")
        #expect(byName["notes.txt"]?.evidence.contains(.lastOpened(Date(timeIntervalSince1970: 1_700_000_000))) == true)
        #expect(findings.allSatisfy { $0.safety == .review && !$0.preselected })
        #expect(findings.first.map { ($0.id as NSString).lastPathComponent } == "Docker.dmg")
    }

    @Test("Finds large files, leaving out apps, ~/Library and hidden folders")
    func largeFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Movies/holiday.mov", bytes: 300_000)
        try fixture.file("Documents/big.pdf", bytes: 150_000)
        try fixture.file("Documents/small.pdf", bytes: 10_000)
        try fixture.file("Library/Containers/vm.img", bytes: 400_000)
        try fixture.file("Tools.app/Contents/Resources/payload.bin", bytes: 500_000)
        try fixture.file(".hidden/secret.bin", bytes: 600_000)
        let finder = PersonalFileFinder(metadata: FakeMetadata(), installedAppNames: [], homeDirectory: fixture.path)

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree
        let names = finder.largeFiles(in: tree, criteria: .init(minimumSize: 100_000)).map { ($0.id as NSString).lastPathComponent }

        #expect(names == ["holiday.mov", "big.pdf"])
    }

    @Test("Leaves out what the user excluded or locked")
    func userRules() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Downloads/Project/archive.zip", bytes: 50_000)
        try fixture.file("Downloads/Keep.dmg", bytes: 40_000)
        try fixture.file("Downloads/Other.dmg", bytes: 30_000)
        let finder = PersonalFileFinder(
            metadata: FakeMetadata(), installedAppNames: [], homeDirectory: fixture.path,
            exclusions: [fixture.path + "/Downloads/Project"], lockedOriginals: [fixture.path + "/Downloads/Keep.dmg"]
        )

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path + "/Downloads")).tree
        let names = finder.downloads(in: tree).map { ($0.id as NSString).lastPathComponent }

        #expect(names == ["Other.dmg"])
    }

    @Test("Can limit large files to ones not opened for a while")
    func notOpenedFilter() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Movies/old.mov", bytes: 300_000)
        try fixture.file("Movies/recent.mov", bytes: 300_000)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let metadata = FakeMetadata(opened: [
            "old.mov": now.addingTimeInterval(-400 * 86_400),
            "recent.mov": now.addingTimeInterval(-10 * 86_400),
        ])
        let finder = PersonalFileFinder(metadata: metadata, installedAppNames: [], homeDirectory: fixture.path, now: { now })

        let tree = try await ScanEngine().scan(ScanScope(path: fixture.path)).tree
        let findings = finder.largeFiles(in: tree, criteria: .init(minimumSize: 100_000, notOpenedForDays: 365))

        #expect(findings.map { ($0.id as NSString).lastPathComponent } == ["old.mov"])
        #expect(findings.first?.evidence.contains(.olderThan(days: 365)) == true)
    }
}

@Suite("InstallerMatcher")
struct InstallerMatcherTests {
    @Test("Reads the app name out of installer file names", arguments: [
        ("Docker.dmg", ["docker"]),
        ("Figma-125.0.dmg", ["figma"]),
        ("Xcode_26.4.xip", ["xcode"]),
        ("GoogleChrome.dmg", ["google", "chrome"]),
        ("VSCode-darwin-universal.zip", ["vscode"]),
        ("Slack-4.46.dmg", ["slack"]),
        ("tool-v2.1.tar.gz", ["tool"]),
        ("Raycast_arm64.dmg", ["raycast"]),
    ])
    func words(fileName: String, expected: [String]) {
        #expect(InstallerMatcher.words(ofFileNamed: fileName) == expected)
    }

    @Test("Matches whole words only")
    func matching() {
        let apps = ["Arc", "Google Chrome", "Docker"]
        #expect(InstallerMatcher.installedApp(forFileNamed: "googlechrome.dmg", among: apps) == "Google Chrome")
        #expect(InstallerMatcher.installedApp(forFileNamed: "Docker-Desktop-4.40.dmg", among: apps) == "Docker")
        #expect(InstallerMatcher.installedApp(forFileNamed: "Archive-2019.zip", among: apps) == nil)
        #expect(InstallerMatcher.installedApp(forFileNamed: "Go.pkg", among: ["Go"]) == nil)
    }
}
