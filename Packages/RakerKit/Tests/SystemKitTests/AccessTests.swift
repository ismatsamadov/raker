import Darwin
import Foundation
import RakerModel
import Testing
@testable import SystemKit

@Suite("AccessProbe")
struct AccessProbeTests {
    @Test("Readable folders are granted, refused ones denied, missing ones absent")
    func states() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("raker-access-\(UUID().uuidString)").path
        defer {
            chmod(home + "/.Trash", 0o755)
            try? FileManager.default.removeItem(atPath: home)
        }
        for folder in ["Downloads", ".Trash", "Library/Containers"] {
            try FileManager.default.createDirectory(atPath: home + "/" + folder, withIntermediateDirectories: true)
        }
        try Data().write(to: URL(fileURLWithPath: home + "/Library/Safari"))
        // Without permission to read it, opening the folder fails the way macOS's privacy
        // protection makes it fail.
        chmod(home + "/.Trash", 0)
        let probe = AccessProbe(homeDirectory: home)

        #expect(probe.check(.downloads) == .granted)
        #expect(probe.check(.trash) == .denied)
        #expect(probe.check(.mail) == .absent)
        #expect(probe.check(.safari) == .absent)
        // Opening the Containers folder says nothing about the data inside it.
        #expect(probe.check(.otherAppsData) == .unknown)
        #expect(probe.check(.rootOnly) == .unknown)
    }
}

@Suite("AccessMap")
struct AccessMapTests {
    @Test("Remembers macOS's answers, but not what can be checked again quietly")
    func remembered() {
        var map = AccessMap()
        map[.downloads] = .granted
        map[.desktop] = .denied
        map[.documents] = .unknown
        map[.trash] = .granted
        map[.otherAppsData] = .denied

        #expect(map.remembered == ["downloads": "granted", "desktop": "denied"])
        let restored = AccessMap(remembered: map.remembered)
        #expect(restored[.downloads] == .granted)
        #expect(restored[.desktop] == .denied)
        #expect(restored[.trash] == .unknown)
        #expect(AccessMap(remembered: ["nonsense": "granted", "mail": "maybe"]) == AccessMap())
    }

    @Test("Checks quiet areas any time, and Files & Folders areas once macOS has asked")
    func areasToCheck() {
        var map = AccessMap()
        #expect(Set(map.areasToCheck) == [.trash, .mail, .messages, .safari, .deviceBackups])

        map[.downloads] = .denied
        map[.documents] = .granted
        #expect(map.areasToCheck.contains(.downloads))
        #expect(map.areasToCheck.contains(.documents))
        #expect(!map.areasToCheck.contains(.desktop))
    }

    @Test("Learns from what scans could and couldn't read")
    func learning() {
        let home = "/Users/alex"
        var map = AccessMap()
        map.learn(fromScanOf: home, skipped: [
            SkippedLocation(path: "/Users/alex/Desktop", reason: .permissionDenied(area: .desktop)),
            SkippedLocation(path: "/Users/alex/Library/Mail", reason: .permissionDenied(area: .mail)),
            SkippedLocation(path: "/Users/alex/gone", reason: .notFound),
        ], homeDirectory: home)
        #expect(map[.desktop] == .denied)
        #expect(map[.mail] == .denied)
        #expect(map[.downloads] == .granted)
        #expect(map[.documents] == .granted)

        var narrow = AccessMap()
        narrow.learn(fromScanOf: "/Users/alex/Projects", skipped: [], homeDirectory: home)
        #expect(narrow[.downloads] == .unknown)

        var refused = AccessMap()
        refused.learn(unreadableRoot: "/Users/alex/Downloads", homeDirectory: home)
        #expect(refused[.downloads] == .denied)
        refused.learn(unreadableRoot: "/Users/alex/Library/Keychains", homeDirectory: home)
        #expect(refused[.fullDiskAccess] == .unknown)
    }

    @Test("Coverage counts only areas whose state is known")
    func coverage() {
        var map = AccessMap()
        #expect(map.coverage(of: .fullDiskAccess) == .unknown)
        map[.trash] = .denied
        map[.mail] = .denied
        map[.safari] = .absent
        map[.fullDiskAccess] = .granted
        #expect(map.coverage(of: .fullDiskAccess) == .none)
        map[.mail] = .granted
        #expect(map.coverage(of: .fullDiskAccess) == .some)
        map[.trash] = .granted
        #expect(map.coverage(of: .fullDiskAccess) == .all)
    }
}

@Suite("ProtectedArea")
struct ProtectedAreaTests {
    @Test("Says which area protects a path", arguments: [
        ("/Users/alex/Downloads", ProtectedArea.downloads),
        ("/Users/alex/Downloads/Docker.dmg", .downloads),
        ("/Users/alex/DownloadsArchive", .fullDiskAccess),
        ("/Users/alex/.Trash/old.zip", .trash),
        ("/Users/alex/Library/Mail/V10", .mail),
        ("/Users/alex/Library/Group Containers/group.example", .otherAppsData),
        ("/Users/alex/Library/Application Support/MobileSync/Backup", .deviceBackups),
        ("/Users/alex/Library/Cookies", .fullDiskAccess),
        ("/Volumes/Backup/data", .removableVolumes),
        ("/private/var/db", .rootOnly),
    ])
    func classify(path: String, area: ProtectedArea) {
        #expect(ProtectedArea.classify(path: path, homeDirectory: "/Users/alex/") == area)
    }
}
