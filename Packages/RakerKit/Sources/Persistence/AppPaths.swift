import Foundation

/// Where Raker keeps its data.
public enum AppPaths {
    /// Placeholder until the bundle identifier is chosen (architecture §21).
    public static let bundleIdentifier = "app.raker"

    /// ~/Library/Application Support/<bundle identifier>
    public static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// The database with cleanup history.
    public static var database: URL {
        applicationSupport.appendingPathComponent("raker.sqlite")
    }
}
