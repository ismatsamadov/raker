import Foundation
import RuleEngine
import Testing
@testable import AppCatalog

@Suite("AssociatedFileFinder")
struct AssociatedFileFinderTests {
    @Test("Finds an app's files and says how sure it is of each")
    func files() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.app("Applications/Example.app", bundleID: "com.example.App", name: "Example")
        for item in [
            "home/Library/Application Support/com.example.App",
            "home/Library/Application Support/Example",
            "home/Library/Caches/com.example.App",
            "home/Library/Preferences/com.example.App.plist",
            "home/Library/Preferences/ByHost/com.example.App.0A1B2C.plist",
            "home/Library/Containers/com.example.App",
            "home/Library/Containers/com.example.App.Helper",
            "home/Library/Group Containers/group.com.example.App",
            "home/Library/Group Containers/ABCDE12345.com.example.shared",
            "home/Library/Saved Application State/com.example.App.savedState",
            "home/Library/HTTPStorages/com.example.App.binarycookies",
            "home/Library/LaunchAgents/com.example.App.updater.plist",
            "home/Library/Caches/com.example.Other",
            "home/Library/Caches/Example Vendor/Studio",
            "home/Library/Application Support/Example Vendor/Studio",
            "C/com.example.App",
        ] {
            try fixture.item(item)
        }
        let environment = PathEnvironment(home: fixture.path + "/home", userRoot: fixture.path, userDirectory: fixture.path + "/0",
                                          userTemporary: fixture.path + "/T", userCache: fixture.path + "/C")
        let app = try #require(AppInventory.info(at: fixture.path + "/Applications/Example.app"))
        let other = AppBundleInfo(path: "/Applications/Other.app", bundleID: "com.example.Other", name: "Other",
                                  version: nil, source: .direct, architecture: .unknown, names: ["Other"])
        let identity = AppIdentity(bundleID: app.bundleID, names: app.names, teamID: "ABCDE12345",
                                   appGroups: ["group.com.example.App", "ABCDE12345.com.example.shared"],
                                   helperIDs: ["com.example.App.Helper"])

        let rule = Rule(id: "example-cache", title: "Example cache", explanation: "e", ifRemoved: "i", category: "caches.apps",
                        safety: .regenerable, targets: [RuleTarget(path: "~/Library/Caches/Example Vendor/Studio", scope: .contents)],
                        appBundleIDs: ["com.example.App"])
        let finder = AssociatedFileFinder(environment: environment, otherApps: [app, other], rules: [rule])
        let files = finder.files(for: app, identity: identity)
        let byName = Dictionary(uniqueKeysWithValues: files.map { ($0.path.replacingOccurrences(of: fixture.path + "/", with: ""), $0) })

        #expect(files.first?.kind == .application)
        #expect(byName["home/Library/Caches/com.example.App"]?.confidence == .high)
        #expect(byName["home/Library/Preferences/ByHost/com.example.App.0A1B2C.plist"]?.kind == .preferences)
        #expect(byName["home/Library/Containers/com.example.App.Helper"]?.reason == .helperID("com.example.App.Helper"))
        #expect(byName["home/Library/Group Containers/group.com.example.App"]?.isPreselected == true)
        // Declared by the app, but not named after it, from a vendor with another app installed: maybe shared.
        let shared = try #require(byName["home/Library/Group Containers/ABCDE12345.com.example.shared"])
        #expect(shared.confidence == .high)
        #expect(shared.isShared)
        #expect(!shared.isPreselected)
        // A rule names the app as the owner of its cache.
        #expect(byName["home/Library/Caches/Example Vendor/Studio"]?.reason == .rule("example-cache"))
        #expect(byName["home/Library/Caches/Example Vendor/Studio"]?.isPreselected == true)
        #expect(byName["home/Library/LaunchAgents/com.example.App.updater.plist"]?.confidence == .medium)
        #expect(byName["home/Library/Application Support/Example"]?.confidence == .low)
        #expect(byName["home/Library/Application Support/Example"]?.isPreselected == false)
        #expect(byName["C/com.example.App"]?.kind == .caches)
        // Another app's files are never listed.
        #expect(byName["home/Library/Caches/com.example.Other"] == nil)
        // The app, ten files named after it, its helper or its group, and the rule's cache.
        #expect(files.filter(\.isPreselected).count == 12)
    }

    @Test("Turns files into findings that go to the Trash while the app isn't running")
    func findings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.app("Applications/Example.app", bundleID: "com.example.App", name: "Example")
        let app = try #require(AppInventory.info(at: fixture.path + "/Applications/Example.app"))
        let file = AppFile(path: app.path, kind: .application, confidence: .high, isShared: false, reason: .bundle)

        let finding = try #require(file.finding(for: app, size: nil))

        #expect(finding.id == "apps:\(app.path)")
        #expect(finding.safety == .review)
        #expect(finding.constraints == [.requiresQuit(bundleID: "com.example.App")])
        #expect(finding.explanation == "The Example app itself.")
    }

    @Test("Only distinctive names are matched against folder names", arguments: [
        ("Slack", true), ("Data", false), ("Logs", false), ("Go", false), ("Notion*", false), ("Google", false),
    ])
    func distinctiveNames(name: String, expected: Bool) {
        #expect(AssociatedFileFinder.isDistinctive(name) == expected)
    }
}
