import Darwin
import Foundation
import Testing
@testable import FileSystemKit

@Suite("SafeRemover")
struct SafeRemoverTests {
    private func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    @Test("Removes a folder tree and counts what it freed")
    func removesTree() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("cache/a.bin", bytes: 40_000)
        try fixture.file("cache/nested/b.bin", bytes: 20_000)
        try fixture.directory("cache/empty")

        let result = SafeRemover.remove(fixture.absolute("cache"))

        #expect(result.error == nil)
        #expect(result.items == 5)
        #expect(result.allocatedBytes >= 60_000)
        #expect(!exists(fixture.absolute("cache")))
    }

    @Test("Removes symlinks but never what they point to")
    func symlinksAreNotFollowed() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("keep/important.txt", bytes: 100)
        try fixture.directory("cache")
        try fixture.symlink("cache/link-to-keep", to: fixture.absolute("keep"))
        try fixture.symlink("cache/link-to-file", to: fixture.absolute("keep/important.txt"))

        let result = SafeRemover.remove(fixture.absolute("cache"))

        #expect(result.error == nil)
        #expect(!exists(fixture.absolute("cache")))
        #expect(exists(fixture.absolute("keep/important.txt")))
    }

    @Test("Refuses a path that goes through a symlinked folder")
    func symlinkInPath() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("real/data.bin", bytes: 100)
        try fixture.symlink("alias", to: fixture.absolute("real"))

        let result = SafeRemover.remove(fixture.absolute("alias/data.bin"))

        #expect(result.error == .symlinkInPath)
        #expect(exists(fixture.absolute("real/data.bin")))
    }

    @Test("Removes read-only folders the user owns, like Go's module cache")
    func readOnlyFolders() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        try fixture.file("modcache/pkg@v1/file.go", bytes: 1_000)
        fixture.setPermissions("modcache/pkg@v1/file.go", 0o444)
        fixture.setPermissions("modcache/pkg@v1", 0o555)
        fixture.setPermissions("modcache", 0o555)

        let result = SafeRemover.remove(fixture.absolute("modcache"))

        #expect(result.error == nil)
        #expect(!exists(fixture.absolute("modcache")))
    }

    @Test("Reports locked files instead of unlocking them")
    func lockedFiles() throws {
        let fixture = try FixtureTree()
        defer {
            chflags(fixture.absolute("cache/locked.bin"), 0)
            fixture.remove()
        }
        try fixture.file("cache/locked.bin", bytes: 100)
        try #require(chflags(fixture.absolute("cache/locked.bin"), UInt32(UF_IMMUTABLE)) == 0)

        let result = SafeRemover.remove(fixture.absolute("cache"))

        #expect(result.error == .locked(path: fixture.absolute("cache/locked.bin")))
        #expect(exists(fixture.absolute("cache/locked.bin")))
    }

    @Test("Rejects relative paths, dot segments and missing items")
    func invalidInput() throws {
        let fixture = try FixtureTree()
        defer { fixture.remove() }
        #expect(SafeRemover.remove("relative/path").error == .invalidPath)
        #expect(SafeRemover.remove("/").error == .invalidPath)
        #expect(SafeRemover.remove(fixture.absolute("a/../b")).error == .invalidPath)
        #expect(SafeRemover.remove(fixture.absolute("missing")).error == .notFound)
    }
}
