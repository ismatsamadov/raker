import Foundation

/// Where a downloaded file came from, as recorded by the app that downloaded it.
public struct DownloadSource: Codable, Sendable, Hashable {
    /// The file's URL first, then the page it was downloaded from, when known.
    public var urls: [String]
    /// The app that downloaded it, such as Safari or Slack.
    public var agent: String?
    public var downloadedAt: Date?

    public init(urls: [String], agent: String?, downloadedAt: Date?) {
        self.urls = urls
        self.agent = agent
        self.downloadedAt = downloadedAt
    }

    /// A short, recognizable origin such as "docker.com": the page's site when known,
    /// otherwise the file's.
    public var site: String? {
        let candidates = urls.count > 1 ? [urls[1], urls[0]] : urls
        for candidate in candidates {
            guard let host = URL(string: candidate)?.host(), !host.isEmpty else { continue }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        return nil
    }
}

/// Facts about files that the file system walk doesn't provide. SystemKit implements it
/// with Spotlight and extended attributes; tests use a fake.
public protocol FileMetadataSource: Sendable {
    /// When the user last opened the file, if macOS recorded it.
    func lastOpened(_ path: String) -> Date?
    func downloadSource(_ path: String) -> DownloadSource?
}
