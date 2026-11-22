import Testing
@testable import SafetyPolicy

@Suite("PathCanonicalizer")
struct PathCanonicalizerTests {
    @Test("Resolves dot segments and repeated separators without touching the disk")
    func lexicalResolution() {
        #expect(PathCanonicalizer.canonicalize("/Users/alex/../alex/./Library//Caches/") == "/Users/alex/Library/Caches")
        #expect(PathCanonicalizer.canonicalize("/../..") == "/")
        #expect(PathCanonicalizer.canonicalize("relative/path") == nil)
    }

    @Test("Maps /var, /tmp, /etc and Data-volume paths to one spelling")
    func aliases() {
        #expect(PathCanonicalizer.canonicalize("/var/folders/x") == "/private/var/folders/x")
        #expect(PathCanonicalizer.canonicalize("/tmp") == "/private/tmp")
        #expect(PathCanonicalizer.canonicalize("/System/Volumes/Data/Users/alex") == "/Users/alex")
        #expect(PathCanonicalizer.canonicalize("/System/Volumes/Data") == "/")
    }

    @Test("Comparison keys ignore case and Unicode normalization")
    func comparisonKey() {
        #expect(PathCanonicalizer.comparisonKey(for: "/SYSTEM/Library") == PathCanonicalizer.comparisonKey(for: "/System/Library"))
        let composed = "/Users/alex/R\u{E9}sum\u{E9}s"
        let decomposed = "/Users/alex/Re\u{301}sume\u{301}s"
        #expect(PathCanonicalizer.comparisonKey(for: composed) == PathCanonicalizer.comparisonKey(for: decomposed))
    }
}

@Suite("SafetyPolicy")
struct SafetyPolicyTests {
    let policy = SafetyPolicy(
        homeDirectory: "/Users/alex",
        exclusions: ["/Users/alex/Library/Caches/Keep Me"],
        lockedOriginals: ["/Users/alex/Pictures/Originals"]
    )

    @Test("System locations are never removable, however they're spelled", arguments: [
        "/System/Library/Fonts",
        "/SYSTEM/library",
        "/usr/bin/ls",
        "/bin",
        "/var/db/receipts",
        "/private/var/vm/swapfile0",
        "/Library/Caches/../../System/Library",
        "/Users/alex/Library/Caches/../../../../System",
        "/System/Volumes/Data/private/var/db",
    ])
    func systemLocations(path: String) {
        #expect(policy.evaluate(path) == .denied(.systemLocation))
    }

    @Test("Roots and container folders can't be removed themselves", arguments: [
        ("/", SafetyPolicy.Reason.volumeRoot),
        ("/System/Volumes/Data", .volumeRoot),
        ("/Volumes/Backup", .volumeRoot),
        ("/Applications", .protectedFolder),
        ("/Users", .protectedFolder),
        ("/Users/alex", .protectedFolder),
        ("/Users/alex/Documents", .protectedFolder),
        ("/Users/alex/Library", .protectedFolder),
        ("/Users/alex/Library/Caches", .protectedFolder),
        ("/Users/alex/.Trash", .protectedFolder),
    ])
    func protectedFolders(path: String, reason: SafetyPolicy.Reason) {
        #expect(policy.evaluate(path) == .denied(reason))
    }

    @Test("Credentials, app databases and other users' data are never removable")
    func sensitiveData() {
        #expect(policy.evaluate("/Users/alex/Library/Keychains/login.keychain-db") == .denied(.credentials))
        #expect(policy.evaluate("/Users/alex/.ssh/id_ed25519") == .denied(.credentials))
        #expect(policy.evaluate("/Users/alex/Library/Messages/chat.db") == .denied(.appDatabases))
        #expect(policy.evaluate("/Users/alex/Library/Mail/V10/MailData") == .denied(.appDatabases))
        #expect(policy.evaluate("/Users/sam/Library/Caches/x") == .denied(.otherUserData))
        #expect(policy.evaluate("/Users/alex/Pictures/Photos Library.photoslibrary/database/Photos.sqlite")
            == .denied(.photosLibraryInternals))
    }

    @Test("Personal files need an explicit selection")
    func personalFiles() {
        #expect(policy.evaluate("/Users/alex/Documents/report.pdf") == .selectionOnly(.personalFiles))
        #expect(policy.evaluate("/Users/alex/Downloads/Installer.dmg") == .selectionOnly(.personalFiles))
        #expect(policy.evaluate("/Users/alex/.Trash/old.zip") == .selectionOnly(.personalFiles))
        #expect(policy.evaluate("/Users/alex/Pictures/Photos Library.photoslibrary") == .selectionOnly(.personalFiles))
        #expect(policy.evaluate("/Volumes/Backup/movie.mov") == .selectionOnly(.personalFiles))
        #expect(policy.evaluate("/Applications/Example.app") == .selectionOnly(.installedApps))
        #expect(policy.evaluate("/Users/alex/Library/Mobile Documents/com~apple~CloudDocs/a.txt")
            == .selectionOnly(.syncedFolder))
    }

    @Test("App caches and temporary folders may be targeted by rules")
    func ruleTargets() {
        #expect(policy.evaluate("/Users/alex/Library/Caches/com.example.app") == .allowed)
        #expect(policy.evaluate("/System/Volumes/Data/Users/alex/Library/Caches/com.example.app") == .allowed)
        #expect(policy.evaluate("/Users/alex/.npm/_cacache") == .allowed)
        #expect(policy.evaluate("/var/folders/xy/abc/C/com.example.app") == .allowed)
        #expect(policy.evaluate("/Library/Caches/com.example.helper") == .allowed)
        #expect(policy.evaluate("/usr/local/Homebrew/Library/Taps/cache") == .allowed)
    }

    @Test("User exclusions and locked originals win over everything")
    func userRules() {
        #expect(policy.evaluate("/Users/alex/Library/Caches/Keep Me/data") == .denied(.userExcluded))
        #expect(policy.evaluate("/users/ALEX/library/caches/keep me") == .denied(.userExcluded))
        #expect(policy.evaluate("/Users/alex/Pictures/Originals/IMG_0001.HEIC") == .denied(.lockedOriginal))
    }

    @Test("Relative paths are refused")
    func relativePaths() {
        #expect(policy.evaluate("Library/Caches") == .denied(.notAbsolute))
        #expect(policy.evaluate("") == .denied(.notAbsolute))
    }

    @Test("Verdict helpers")
    func verdictHelpers() {
        #expect(SafetyPolicy.Verdict.allowed.permitsRules)
        #expect(!SafetyPolicy.Verdict.selectionOnly(.personalFiles).permitsRules)
        #expect(SafetyPolicy.Verdict.selectionOnly(.personalFiles).permitsUserSelection)
        #expect(!SafetyPolicy.Verdict.denied(.credentials).permitsUserSelection)
    }
}
