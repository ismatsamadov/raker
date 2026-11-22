import FileSystemKit
import Foundation
import RakerFoundation
import RakerModel
import SafetyPolicy
import SpaceIndex

/// Finds personal files worth a look: what's in Downloads, and large or long-unopened files
/// anywhere in a scan.
///
/// These are the user's own files, so every finding needs review: nothing is preselected and
/// everything goes to the Trash. Synced files are marked so they're never removed here.
public struct PersonalFileFinder: Sendable {
    public struct LargeFileCriteria: Sendable, Hashable {
        public var minimumSize: UInt64
        /// Only files not opened for this many days; nil for any.
        public var notOpenedForDays: Int?

        public init(minimumSize: UInt64 = 50_000_000, notOpenedForDays: Int? = nil) {
            self.minimumSize = minimumSize
            self.notOpenedForDays = notOpenedForDays
        }
    }

    private let metadata: any FileMetadataSource
    private let installedAppNames: [String]
    private let policy: SafetyPolicy
    private let homeDirectory: String
    private let now: @Sendable () -> Date

    public init(
        metadata: any FileMetadataSource,
        installedAppNames: [String],
        homeDirectory: String = NSHomeDirectory(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.metadata = metadata
        self.installedAppNames = installedAppNames
        self.policy = SafetyPolicy(homeDirectory: homeDirectory)
        self.homeDirectory = homeDirectory
        self.now = now
    }

    /// Everything at the top level of a scanned Downloads folder, largest first.
    public func downloads(in tree: SizeTree) -> [Finding] {
        tree.largestChildren(of: tree.root).compactMap { index in
            let name = tree.name(of: index)
            guard !tree.flags(of: index).contains(.hidden), name != "Icon\r" else { return nil }
            let kind = Self.kind(of: index, in: tree)
            return finding(
                index: index, in: tree, idPrefix: "downloads",
                category: "downloads.\(kind.rawValue)",
                explanation: Self.explanation(for: kind),
                matchesApp: kind == .installers || kind == .archives || kind == .apps
            )
        }
    }

    /// Files at least `criteria.minimumSize` on disk, optionally not opened for a while,
    /// largest first. App bundles, Photos libraries, ~/Library and hidden folders are left out:
    /// they aren't loose personal files.
    public func largeFiles(in tree: SizeTree, criteria: LargeFileCriteria, limit: Int = 500) -> [Finding] {
        var candidates: [SizeTree.Index] = []
        var stack = [tree.root]
        let library = Paths.join(homeDirectory, "Library")
        while let current = stack.popLast() {
            for child in tree.children(of: current) {
                let flags = tree.flags(of: child)
                if flags.contains(.hidden) { continue }
                switch tree.kind(of: child) {
                case .directory:
                    let name = tree.name(of: child)
                    if Self.isPackage(name) || tree.path(of: child) == library { continue }
                    stack.append(child)
                case .file:
                    if tree.allocatedSize(of: child) >= criteria.minimumSize { candidates.append(child) }
                case .symlink, .other:
                    continue
                }
            }
        }
        candidates.sort { tree.allocatedSize(of: $0) > tree.allocatedSize(of: $1) }

        let cutoff = criteria.notOpenedForDays.map { now().addingTimeInterval(-Double($0) * 86_400) }
        var findings: [Finding] = []
        for index in candidates {
            if let cutoff {
                let path = tree.path(of: index)
                let used = metadata.lastOpened(path) ?? tree.modificationDate(of: index)
                guard used < cutoff else { continue }
            }
            let kind = StorageKindClassifier.kind(ofFileNamed: tree.name(of: index))
            guard let finding = finding(
                index: index, in: tree, idPrefix: "large", category: "large.\(kind.rawValue)",
                explanation: "A large file. Only you can tell whether you still need it.", matchesApp: false,
                extraEvidence: [.largerThan(bytes: criteria.minimumSize)]
                    + (criteria.notOpenedForDays.map { [.olderThan(days: $0)] } ?? [])
            ) else { continue }
            findings.append(finding)
            if findings.count == limit { break }
        }
        return findings
    }

    // MARK: - Building findings

    private func finding(
        index: SizeTree.Index,
        in tree: SizeTree,
        idPrefix: String,
        category: String,
        explanation: String,
        matchesApp: Bool,
        extraEvidence: [Evidence] = []
    ) -> Finding? {
        let path = tree.path(of: index)
        guard policy.evaluate(path).permitsUserSelection, let status = try? FileStatus.of(path), !status.isSymlink else {
            return nil
        }
        var evidence = extraEvidence
        if let source = metadata.downloadSource(path), let site = source.site {
            evidence.append(.downloadedFrom(site))
        }
        if let opened = metadata.lastOpened(path) {
            evidence.append(.lastOpened(opened))
        }
        if matchesApp, let app = InstallerMatcher.installedApp(forFileNamed: tree.name(of: index), among: installedAppNames) {
            evidence.append(.appInstalled(name: app))
        }
        var constraints: [Constraint] = []
        if tree.flags(of: index).contains(.dataless) || policy.evaluate(path) == .selectionOnly(.syncedFolder) {
            constraints.append(.synced(provider: "cloud"))
        }
        return Finding(
            id: "\(idPrefix):\(path)",
            subject: .file(FileRef(path: path, identity: status.identity)),
            category: CategoryID(rawValue: category),
            safety: .review,
            size: tree.size(of: index),
            evidence: evidence,
            explanation: explanation,
            constraints: constraints
        )
    }

    static func kind(of index: SizeTree.Index, in tree: SizeTree) -> StorageKind {
        let name = tree.name(of: index)
        if tree.kind(of: index) == .directory {
            return Paths.pathExtension(name) == "app" ? .apps : .other
        }
        return StorageKindClassifier.kind(ofFileNamed: name)
    }

    static func explanation(for kind: StorageKind) -> String {
        switch kind {
        case .installers: "An installer. Once the app is installed, you can usually download it again if you need it."
        case .archives: "A compressed archive. It may be your only copy of what's inside, so check before removing it."
        case .apps: "An app that was never moved to Applications."
        case .media: "A photo, video or audio file."
        case .documents: "A document."
        case .developer, .other: "Something you downloaded."
        }
    }

    static func isPackage(_ name: String) -> Bool {
        ["app", "photoslibrary", "musiclibrary", "tvlibrary", "bundle", "framework", "plugin", "xcarchive", "pkg", "fcpbundle"]
            .contains(Paths.pathExtension(name))
    }
}

/// Matches installer and archive names such as "Docker.dmg" or "Figma-125.0.dmg" to installed
/// apps by whole words, so "Archive-2019.zip" never matches an app called "Arc".
enum InstallerMatcher {
    static func installedApp(forFileNamed fileName: String, among apps: [String]) -> String? {
        let fileWords = words(ofFileNamed: fileName)
        guard !fileWords.isEmpty else { return nil }
        let joinedFile = fileWords.joined()
        for app in apps {
            let appWords = words(of: app)
            guard !appWords.isEmpty, appWords.joined().count >= 3 else { continue }
            if appWords.joined() == joinedFile || fileWords.starts(with: appWords) {
                return app
            }
        }
        return nil
    }

    /// Lowercased words of a file name up to the first version number or platform word.
    static func words(ofFileNamed fileName: String) -> [String] {
        var base = fileName
        for suffix in [".tar.gz", ".tar.bz2", ".tar.xz"] where base.lowercased().hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        if base == fileName, let dot = base.lastIndex(of: "."), dot != base.startIndex {
            base = String(base[..<dot])
        }
        let stopWords: Set = ["darwin", "mac", "macos", "osx", "universal", "arm", "amd", "aarch", "x", "intel",
                              "apple", "silicon", "installer", "setup", "latest", "release", "stable", "v"]
        var result: [String] = []
        for word in words(of: base) {
            if word.first?.isNumber == true || stopWords.contains(word) { break }
            result.append(word)
        }
        return result
    }

    /// Words split at non-alphanumerics and lower-to-upper case changes ("GoogleChrome" → google, chrome).
    static func words(of text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for character in text {
            if character.isLetter || character.isNumber {
                let startsWord = previous.map { $0.isLowercase && character.isUppercase || $0.isLetter != character.isLetter } ?? false
                if startsWord, !current.isEmpty {
                    words.append(current.lowercased())
                    current = ""
                }
                current.append(character)
            } else if !current.isEmpty {
                words.append(current.lowercased())
                current = ""
            }
            previous = character
        }
        if !current.isEmpty { words.append(current.lowercased()) }
        return words
    }
}
