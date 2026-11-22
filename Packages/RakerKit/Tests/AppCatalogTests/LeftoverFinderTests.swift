import Foundation
import RakerModel
import RuleEngine
import Testing
@testable import AppCatalog

/// Apps Launch Services knows, by bundle ID and path.
private struct FakeApps: AppDirectory {
    var installed: [String: String] = [:]

    func installedApp(bundleID: String) -> InstalledApp? {
        installed[bundleID].map { InstalledApp(bundleID: bundleID, name: bundleID, path: $0) }
    }

    func isRunning(bundleID: String) -> Bool { false }
}

@Suite("LeftoverFinder")
struct LeftoverFinderTests {
    @Test("Lists what removed apps left behind, only for IDs macOS knew as apps")
    func leftovers() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for item in [
            // A removed sandboxed app, its extension and its files.
            "home/Library/Containers/com.gone.App",
            "home/Library/Containers/com.gone.App.ShareExtension",
            "home/Library/Caches/com.gone.App",
            "home/Library/Preferences/com.gone.App.plist",
            "home/Library/Group Containers/group.com.gone.App",
            "home/Library/HTTPStorages/com.gone.App.binarycookies",
            // A group of the removed app that an installed app declares too.
            "home/Library/Group Containers/group.com.gone.App.sync",
            // A removed app whose vendor still has an app installed.
            "home/Library/Saved Application State/com.vendor.Removed.savedState",
            "home/Library/Caches/com.vendor.Removed",
            // An installed app, its widget and its helper.
            "home/Library/Containers/com.installed.App",
            "home/Library/Containers/com.installed.App.Widget",
            "home/Library/Containers/com.helper.Agent",
            // Apps Launch Services knows: one outside the Applications folders, one in the Trash.
            "home/Library/Containers/com.elsewhere.App",
            "home/Library/Containers/com.trashed.App",
            // Named like apps, with nothing to show they were: a tool's files and Shortcuts' data.
            "home/Library/Application Support/org.swift.swiftpm",
            "home/Library/Caches/org.swift.swiftpm",
            "home/Library/Group Containers/group.is.workflow.shortcuts",
            // Apple's.
            "home/Library/Containers/com.apple.Notes",
            "home/Library/Saved Application State/com.apple.Safari.savedState",
            "home/Library/Group Containers/group.com.apple.notes",
        ] {
            try fixture.item(item)
        }
        try fixture.item("bin/agent")
        let agents = fixture.path + "/home/Library/LaunchAgents"
        try FileManager.default.createDirectory(atPath: agents, withIntermediateDirectories: true)
        for (label, program) in [
            // Its program is gone: left by software that's gone.
            ("com.dead.Updater", fixture.path + "/gone/updater"),
            // Still starts something, so it's not a leftover on its own...
            ("com.alive.Agent", fixture.path + "/bin/agent"),
            // ...unless it belongs to a removed app.
            ("com.gone.App.helper", fixture.path + "/bin/agent"),
            // Programs on other volumes may only be unplugged.
            ("com.external.Tool", "/Volumes/Raker Test Volume/tool"),
        ] {
            try PropertyListSerialization.data(fromPropertyList: ["Label": label, "ProgramArguments": [program, "--run"]],
                                               format: .xml, options: 0)
                .write(to: URL(fileURLWithPath: agents + "/\(label).plist"))
        }

        let environment = PathEnvironment(home: fixture.path + "/home", userRoot: fixture.path, userDirectory: fixture.path + "/0",
                                          userTemporary: fixture.path + "/T", userCache: fixture.path + "/C")
        let installed = [
            AppIdentity(bundleID: "com.installed.App", names: ["Installed"], appGroups: ["group.com.gone.App.sync"],
                        helperIDs: ["com.helper.Agent"]),
            AppIdentity(bundleID: "com.vendor.Kept", names: ["Kept"]),
        ]
        let apps = FakeApps(installed: [
            "com.elsewhere.App": "/Users/alex/Downloads/Elsewhere.app",
            "com.trashed.App": "/Users/alex/.Trash/Trashed.app",
        ])
        let leftovers = LeftoverFinder(environment: environment, apps: apps, installed: installed).leftovers()

        #expect(leftovers.map(\.bundleID) == ["com.dead.Updater", "com.gone.App", "com.trashed.App", "com.vendor.Removed"])
        let gone = try #require(leftovers.first { $0.bundleID == "com.gone.App" })
        let library = fixture.path + "/home/Library/"
        #expect(Set(gone.files.map { $0.path.replacingOccurrences(of: library, with: "") }) == [
            "Containers/com.gone.App", "Containers/com.gone.App.ShareExtension", "Caches/com.gone.App",
            "Preferences/com.gone.App.plist", "Group Containers/group.com.gone.App",
            "HTTPStorages/com.gone.App.binarycookies", "LaunchAgents/com.gone.App.helper.plist",
        ])
        // In the uninstaller's order of kinds.
        #expect(gone.files.map(\.kind) == [.caches, .preferences, .container, .container, .groupContainer, .webData, .launchAgent])
        #expect(gone.files.allSatisfy { $0.isPreselected })
        // Another app from the vendor may share them, so they're never chosen for you.
        let removed = try #require(leftovers.first { $0.bundleID == "com.vendor.Removed" })
        #expect(removed.files.count == 2)
        #expect(removed.files.allSatisfy { $0.isShared && !$0.isPreselected })
    }

    @Test("An app counts as installed again only outside the Trash")
    func installedAgain() {
        let apps = FakeApps(installed: [
            "com.back.App": "/Applications/Back.app",
            "com.trashed.App": "/Users/alex/.Trash/Trashed.app",
        ])
        #expect(LeftoverFinder.isInstalled("com.back.App", apps: apps))
        #expect(LeftoverFinder.isInstalled("com.back.App.Helper", apps: apps))
        #expect(!LeftoverFinder.isInstalled("com.trashed.App", apps: apps))
        #expect(!LeftoverFinder.isInstalled("com.gone.App", apps: apps))

        // Staged leftovers of an app that's back are its data again.
        func staged(_ bundleID: String) -> Finding {
            Finding(id: "leftovers:/Users/alex/Library/Caches/\(bundleID)",
                    subject: .file(FileRef(path: "/Users/alex/Library/Caches/\(bundleID)",
                                           identity: FileIdentity(device: 1, inode: 42, size: 1, modificationTime: 0))),
                    category: "apps.caches", safety: .review, size: SizeEstimate(logical: 1, allocated: 1, reclaimable: nil),
                    evidence: [.ownerNotInstalled(bundleID: bundleID)], explanation: "")
        }
        #expect(LeftoverFinder.reinstalled([staged("com.back.App"), staged("com.gone.App")], apps: apps)
            == ["leftovers:/Users/alex/Library/Caches/com.back.App"])
    }

    @Test("Reads the app ID inside a group's name")
    func groups() {
        #expect(LeftoverFinder.group("group.com.vendor.App")?.id == "com.vendor.App")
        #expect(LeftoverFinder.group("ABCDE12345.com.vendor.App")?.team == "ABCDE12345")
        #expect(LeftoverFinder.group("ABCDE12345.com.vendor.App")?.id == "com.vendor.App")
        #expect(LeftoverFinder.group("com.vendor.App") == nil)
    }

    @Test("Turns leftovers into findings that go to the Trash")
    func findings() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.item("home/Library/Caches/com.gone.App")
        let file = AppFile(path: fixture.path + "/home/Library/Caches/com.gone.App", kind: .caches, confidence: .high,
                           isShared: false, reason: .bundleID)

        let finding = try #require(file.finding(leftBy: "com.gone.App", size: nil))

        #expect(finding.id == "leftovers:\(file.path)")
        #expect(finding.safety == .review)
        #expect(finding.evidence == [.ownerNotInstalled(bundleID: "com.gone.App")])
        #expect(finding.constraints == [.requiresQuit(bundleID: "com.gone.App")])
        #expect(finding.explanation == "Left behind by com.gone.App, which is no longer installed: data it kept to work faster.")
    }
}
