import CoreServices
import Darwin
import Foundation
import RakerModel

/// Last-opened dates from Spotlight, and download origins from the extended attributes
/// browsers and chat apps attach to downloads.
public struct SystemFileMetadata: FileMetadataSource {
    public init() {}

    public func lastOpened(_ path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    public func downloadSource(_ path: String) -> DownloadSource? {
        let urls = whereFroms(path)
        let quarantine = quarantine(path)
        guard !urls.isEmpty || quarantine != nil else { return nil }
        return DownloadSource(urls: urls, agent: quarantine?.agent, downloadedAt: quarantine?.date)
    }

    /// The URLs recorded in `com.apple.metadata:kMDItemWhereFroms`.
    private func whereFroms(_ path: String) -> [String] {
        guard let data = attribute("com.apple.metadata:kMDItemWhereFroms", of: path),
              let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return [] }
        return list.filter { !$0.isEmpty }
    }

    /// `com.apple.quarantine` reads "flags;hex seconds since 1970;agent;event ID".
    private func quarantine(_ path: String) -> (agent: String?, date: Date?)? {
        guard let data = attribute("com.apple.quarantine", of: path),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let fields = text.split(separator: ";", omittingEmptySubsequences: false)
        let date = fields.count > 1 ? UInt64(fields[1], radix: 16).map { Date(timeIntervalSince1970: TimeInterval($0)) } : nil
        let agent = fields.count > 2 && !fields[2].isEmpty ? String(fields[2]) : nil
        return (agent, date)
    }

    private func attribute(_ name: String, of path: String) -> Data? {
        let size = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, name, buffer.baseAddress, size, 0, XATTR_NOFOLLOW)
        }
        return read > 0 ? data.prefix(read) : nil
    }
}

/// Apps in the standard Applications folders.
public enum ApplicationsFolder {
    /// Names of installed apps, without ".app".
    public static func installedAppNames(home: String = NSHomeDirectory()) -> [String] {
        let folders = ["/Applications", "/Applications/Utilities", "/Applications/Setapp", home + "/Applications"]
        var names: [String] = []
        for folder in folders {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            names += entries.filter { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }
        }
        return names
    }
}
