import Foundation
import Testing
@testable import AppCatalog

@Suite("AppInventory")
struct AppInventoryTests {
    @Test("Finds apps, one folder deep, and reads where they came from and what they run on")
    func inventory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.app("Applications/Example.app", bundleID: "com.example.App", name: "Example", version: "2.1",
                        executable: universalHeader)
        try fixture.app("Applications/Store.app", bundleID: "com.store.App", executable: armHeader, receipt: true)
        try fixture.app("Applications/Vendor/Tool.app", bundleID: "com.vendor.Tool", executable: intelHeader)
        try fixture.app("Applications/Safari.app", bundleID: "com.apple.Safari")
        try FileManager.default.createDirectory(atPath: fixture.path + "/Applications/Broken.app", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: fixture.path + "/Applications/Alias.app",
                                                   withDestinationPath: fixture.path + "/Applications/Example.app")

        let apps = AppInventory(folders: [fixture.path + "/Applications"]).apps()

        #expect(apps.map(\.name) == ["Example", "Safari", "Store", "Tool"])
        let byID = Dictionary(uniqueKeysWithValues: apps.map { ($0.bundleID, $0) })
        #expect(byID["com.example.App"]?.version == "2.1")
        #expect(byID["com.example.App"]?.architecture == .universal)
        #expect(byID["com.example.App"]?.source == .direct)
        #expect(byID["com.store.App"]?.source == .appStore)
        #expect(byID["com.store.App"]?.architecture == .appleSilicon)
        #expect(byID["com.vendor.Tool"]?.architecture == .intel)
        #expect(byID["com.apple.Safari"]?.source == .apple)
        #expect(byID["com.apple.Safari"]?.isRemovable == false)
        #expect(byID["com.apple.Safari"]?.architecture == .unknown)
    }

    @Test("Reads processor types from Mach-O headers")
    func machO() {
        #expect(MachO.cpuTypes(in: Data(universalHeader)) == [0x0100_0007, 0x0100_000C])
        #expect(MachO.cpuTypes(in: Data(armHeader)) == [0x0100_000C])
        #expect(MachO.cpuTypes(in: Data("#!/bin/sh\n".utf8)).isEmpty)
    }
}
