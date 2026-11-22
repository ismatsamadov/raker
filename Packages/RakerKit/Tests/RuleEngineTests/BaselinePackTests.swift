import Testing
@testable import RuleEngine

private let testEnvironment = PathEnvironment(
    home: "/Users/alex",
    userRoot: "/private/var/folders/ab/cd",
    userDirectory: "/private/var/folders/ab/cd/0",
    userTemporary: "/private/var/folders/ab/cd/T",
    userCache: "/private/var/folders/ab/cd/C"
)

@Suite("Baseline pack")
struct BaselinePackTests {
    @Test("The baseline pack loads and passes validation")
    func baselinePack() throws {
        let pack = try RulePackLoader.baseline()
        #expect(pack.schema == RulePack.supportedSchema)
        #expect(!pack.rules.isEmpty)
        #expect(!pack.locations.isEmpty)
        try RulePackLoader.validate(pack, environment: testEnvironment)
        try RulePackLoader.validate(pack, environment: .current())
    }

    @Test("Specific rules come before the generic cache rule that would swallow them")
    func baselineOrdering() throws {
        let ids = try RulePackLoader.baseline().rules.map(\.id)
        let generic = try #require(ids.firstIndex(of: "apps.caches"))
        for specific in ["browser.chrome.cache", "dev.go.buildCache", "dev.homebrew.downloads", "macos.caches"] {
            #expect(try #require(ids.firstIndex(of: specific)) < generic)
        }
    }
}
