/// An installed app, as Launch Services knows it.
public struct InstalledApp: Codable, Sendable, Hashable {
    public var bundleID: String
    public var name: String
    public var path: String

    public init(bundleID: String, name: String, path: String) {
        self.bundleID = bundleID
        self.name = name
        self.path = path
    }
}

/// Looks up installed and running apps. SystemKit implements it with Launch Services;
/// tests use a fake.
public protocol AppDirectory: Sendable {
    func installedApp(bundleID: String) -> InstalledApp?
    func isRunning(bundleID: String) -> Bool
}
