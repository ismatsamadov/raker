import os

/// Unified-logging categories, one per area of the app.
///
/// Log file paths with `privacy: .private` so they are redacted in shared logs.
public enum Log {
    public static let subsystem = "app.raker"

    public static let scan = Logger(subsystem: subsystem, category: "scan")
    public static let safety = Logger(subsystem: subsystem, category: "safety")
    public static let clean = Logger(subsystem: subsystem, category: "clean")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
}
