import AppKit
import RakerModel
import Synchronization

/// Finds installed and running apps through Launch Services. Lookups are cached, because a
/// scan asks about the same bundle IDs many times.
public final class LaunchServicesAppDirectory: AppDirectory {
    /// `nil` values remember that no app is installed for an ID.
    private let cache = Mutex<[String: InstalledApp?]>([:])

    public init() {}

    public func installedApp(bundleID: String) -> InstalledApp? {
        if let cached = cache.withLock({ $0[bundleID] }) {
            return cached
        }
        let app = Self.lookUp(bundleID)
        cache.withLock { $0[bundleID] = app }
        return app
    }

    public func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func lookUp(_ bundleID: String) -> InstalledApp? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let displayName = FileManager.default.displayName(atPath: url.path)
        let name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
        return InstalledApp(bundleID: bundleID, name: name, path: url.path)
    }
}
