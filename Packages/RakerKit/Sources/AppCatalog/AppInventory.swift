import Foundation
import RakerFoundation

/// An app bundle on disk, with what its bundle says about it.
public struct AppBundleInfo: Codable, Sendable, Hashable, Identifiable {
    public enum Source: String, Codable, Sendable {
        case appStore
        case setapp
        /// Part of macOS; it can't be removed.
        case apple
        case direct
    }

    public enum Architecture: String, Codable, Sendable {
        case universal
        case appleSilicon
        /// Runs through Rosetta 2 on Apple silicon.
        case intel
        case unknown
    }

    public var path: String
    public var bundleID: String
    public var name: String
    public var version: String?
    public var source: Source
    public var architecture: Architecture

    public var id: String { path }

    /// Names the app might use for its folders: its display name, bundle name and file name.
    public var names: [String]

    public init(path: String, bundleID: String, name: String, version: String?, source: Source,
                architecture: Architecture, names: [String]) {
        self.path = path
        self.bundleID = bundleID
        self.name = name
        self.version = version
        self.source = source
        self.architecture = architecture
        self.names = names
    }

    /// Whether Raker may offer to remove it. Apps that are part of macOS are protected by
    /// the system, and removing them isn't supported.
    public var isRemovable: Bool { source != .apple }
}

/// Finds the apps in the standard Applications folders.
public struct AppInventory: Sendable {
    private let folders: [String]

    public init(folders: [String] = AppInventory.standardFolders()) {
        self.folders = folders
    }

    public static func standardFolders(home: String = NSHomeDirectory()) -> [String] {
        ["/Applications", Paths.join(home, "Applications")]
    }

    /// Apps in the folders and one level of subfolders, such as "Utilities" or a vendor's
    /// folder, sorted by name. Symlinks are skipped, so nothing is listed twice.
    public func apps() -> [AppBundleInfo] {
        var found: [String: AppBundleInfo] = [:]
        for folder in folders {
            for name in Self.entries(of: folder) {
                let path = Paths.join(folder, name)
                if name.hasSuffix(".app") {
                    if let app = Self.info(at: path) { found[path] = app }
                } else if Self.isFolder(path) {
                    for inner in Self.entries(of: path) where inner.hasSuffix(".app") {
                        let innerPath = Paths.join(path, inner)
                        if let app = Self.info(at: innerPath) { found[innerPath] = app }
                    }
                }
            }
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Reads an app bundle's Info.plist, receipt and executable.
    public static func info(at path: String) -> AppBundleInfo? {
        guard isFolder(path), !isSymlink(path),
              let plist = NSDictionary(contentsOfFile: Paths.join(path, "Contents/Info.plist")) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty
        else { return nil }
        let fileName = String(Paths.lastComponent(path).dropLast(4))
        let displayName = plist["CFBundleDisplayName"] as? String
        let bundleName = plist["CFBundleName"] as? String
        let name = [displayName, bundleName].compactMap { $0 }.first { !$0.isEmpty } ?? fileName
        var names: [String] = []
        for candidate in [fileName, displayName, bundleName].compactMap({ $0 }) where !names.contains(candidate) {
            names.append(candidate)
        }

        let source: AppBundleInfo.Source
        if FileManager.default.fileExists(atPath: Paths.join(path, "Contents/_MASReceipt/receipt")) {
            source = .appStore
        } else if path.hasPrefix("/Applications/Setapp/") {
            source = .setapp
        } else if bundleID.hasPrefix("com.apple.") {
            source = .apple
        } else {
            source = .direct
        }

        var architecture = AppBundleInfo.Architecture.unknown
        if let executable = plist["CFBundleExecutable"] as? String {
            architecture = MachO.architecture(ofExecutableAt: Paths.join(path, "Contents/MacOS/" + executable))
        }
        return AppBundleInfo(path: path, bundleID: bundleID, name: name,
                             version: plist["CFBundleShortVersionString"] as? String,
                             source: source, architecture: architecture, names: names)
    }

    private static func entries(of folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { !$0.hasPrefix(".") }
    }

    private static func isFolder(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private static func isSymlink(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFLNK
    }
}

/// Reads which processors an executable was built for, from its Mach-O header.
enum MachO {
    private static let arm64: UInt32 = 0x0100_000C
    private static let x86_64: UInt32 = 0x0100_0007

    static func architecture(ofExecutableAt path: String) -> AppBundleInfo.Architecture {
        guard let handle = FileHandle(forReadingAtPath: path) else { return .unknown }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 4096), header.count >= 8 else { return .unknown }
        let types = cpuTypes(in: header)
        switch (types.contains(arm64), types.contains(x86_64)) {
        case (true, true): return .universal
        case (true, false): return .appleSilicon
        case (false, true): return .intel
        case (false, false): return .unknown
        }
    }

    static func cpuTypes(in header: Data) -> Set<UInt32> {
        let bytes = [UInt8](header)
        func bigEndian(_ offset: Int) -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            return bytes[offset ..< offset + 4].reduce(0) { $0 << 8 | UInt32($1) }
        }
        func littleEndian(_ offset: Int) -> UInt32? {
            guard offset + 4 <= bytes.count else { return nil }
            return bytes[offset ..< offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }
        }
        guard let magic = bigEndian(0) else { return [] }
        switch magic {
        case 0xCAFE_BABE, 0xCAFE_BABF:
            // A universal binary: a big-endian table of slices, 20 or 32 bytes each.
            let entrySize = magic == 0xCAFE_BABE ? 20 : 32
            guard let count = bigEndian(4), count < 32 else { return [] }
            return Set((0 ..< Int(count)).compactMap { bigEndian(8 + $0 * entrySize) })
        case 0xCFFA_EDFE, 0xCEFA_EDFE:
            // A single little-endian slice.
            return littleEndian(4).map { [$0] } ?? []
        default:
            return []
        }
    }
}
