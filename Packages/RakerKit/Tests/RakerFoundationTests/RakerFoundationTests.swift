import Foundation
import Testing
@testable import RakerFoundation

@Suite("ByteCount")
struct ByteCountTests {
    @Test("Formats with decimal units, like Finder")
    func decimalUnits() {
        // With binary units these would read 977 KB and 954 MB.
        #expect(ByteCount(1_000_000).formatted.hasPrefix("1"))
        #expect(ByteCount(1_000_000_000).formatted.hasPrefix("1"))
        #expect(ByteCount(999).formatted.contains("999"))
        #expect(ByteCount(0).formatted.contains("0"))
    }

    @Test("Addition saturates instead of overflowing")
    func saturatingAddition() {
        #expect(ByteCount(.max) + ByteCount(1) == ByteCount(.max))
        var total = ByteCount.zero
        total += 40
        total += 2
        #expect(total == 42)
    }

    @Test("Encodes as a bare number")
    func codable() throws {
        let data = try JSONEncoder().encode(ByteCount(4_096))
        #expect(String(decoding: data, as: UTF8.self) == "4096")
        #expect(try JSONDecoder().decode(ByteCount.self, from: data) == 4_096)
    }
}

@Suite("Paths")
struct PathsTests {
    @Test func join() {
        #expect(Paths.join("/Users/alex", "Library") == "/Users/alex/Library")
        #expect(Paths.join("/", "Users") == "/Users")
        #expect(Paths.join("/tmp/", "x") == "/tmp/x")
    }

    @Test func lastComponent() {
        #expect(Paths.lastComponent("/Users/alex/report.pdf") == "report.pdf")
        #expect(Paths.lastComponent("/") == "/")
        #expect(Paths.lastComponent("name") == "name")
    }

    @Test func pathExtension() {
        #expect(Paths.pathExtension("Installer.DMG") == "dmg")
        #expect(Paths.pathExtension("archive.tar.gz") == "gz")
        #expect(Paths.pathExtension(".zshrc") == "")
        #expect(Paths.pathExtension("README") == "")
    }
}
