import FileSystemKit
import RakerFoundation
import SpaceIndex

/// Broad categories that make a scan's contents recognizable at a glance.
public enum StorageKind: String, CaseIterable, Sendable, Codable {
    case apps
    case installers
    case archives
    case media
    case documents
    case developer
    case other
}

public enum StorageKindClassifier {
    static let installers: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso", "ipsw"]
    static let archives: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst"]
    static let media: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "webp", "raw", "dng", "cr2", "cr3",
        "nef", "arw", "psd", "mov", "mp4", "m4v", "mkv", "avi", "webm", "mp3", "m4a", "aac", "wav",
        "aif", "aiff", "flac", "ogg",
    ]
    static let documents: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "rtf",
        "md", "csv", "epub", "odt", "ods",
    ]
    static let developerFolders: Set<String> = [
        "node_modules", "DerivedData", ".build", "Pods", ".gradle", ".venv", "__pycache__",
    ]

    public static func kind(ofFileNamed name: String) -> StorageKind {
        let pathExtension = Paths.pathExtension(name)
        if installers.contains(pathExtension) { return .installers }
        if archives.contains(pathExtension) { return .archives }
        if media.contains(pathExtension) { return .media }
        if documents.contains(pathExtension) { return .documents }
        return .other
    }

    /// Allocated bytes per kind below `index`. Apps and developer folders count as one item each.
    public static func breakdown(of tree: SizeTree, under index: SizeTree.Index) -> [StorageKind: UInt64] {
        var totals: [StorageKind: UInt64] = [:]
        var stack = [index]
        while let current = stack.popLast() {
            for child in tree.children(of: current) {
                let name = tree.name(of: child)
                switch tree.kind(of: child) {
                case .directory:
                    if Paths.pathExtension(name) == "app" {
                        totals[.apps, default: 0] &+= tree.allocatedSize(of: child)
                    } else if developerFolders.contains(name) {
                        totals[.developer, default: 0] &+= tree.allocatedSize(of: child)
                    } else {
                        stack.append(child)
                    }
                case .file:
                    totals[kind(ofFileNamed: name), default: 0] &+= tree.allocatedSize(of: child)
                case .symlink, .other:
                    totals[.other, default: 0] &+= tree.allocatedSize(of: child)
                }
            }
        }
        return totals
    }
}
