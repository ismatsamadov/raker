import Foundation

/// How careful the user must be with a finding.
public enum SafetyLevel: Int, Codable, Sendable, Comparable, CaseIterable {
    /// Caches, logs and build output that the owning app recreates.
    case regenerable
    /// Personal data or a judgment call. Never preselected.
    case review
    /// System-level or lossy. Hidden unless Expert mode is on.
    case expert

    public static func < (lhs: SafetyLevel, rhs: SafetyLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A stable, dotted category name such as "downloads.installers".
public struct CategoryID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }
}

/// Why something was found.
public enum Evidence: Codable, Sendable, Hashable {
    case rule(id: String)
    case downloadedFrom(String)
    case lastOpened(Date)
    case largerThan(bytes: UInt64)
    case olderThan(days: Int)
    case matchedBundleID(String)
    /// The app or tool that owns the item, identified from its folder name.
    case owner(name: String, bundleID: String?)
    /// The folder is named after an app, but no installed app uses that name.
    case ownerNotInstalled(bundleID: String)
}

/// Conditions that must hold before a finding can be acted on.
public enum Constraint: Codable, Sendable, Hashable {
    case requiresQuit(bundleID: String)
    case requiresHelper
    case synced(provider: String)
    case notRestorable
}

/// What a finding is about.
public enum Subject: Codable, Sendable, Hashable {
    case file(FileRef)
    case duplicateSet(id: String)
    case app(bundleID: String, path: String)
    case action(id: String)
}

/// A candidate for cleanup, with everything the review screen needs to explain it.
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var subject: Subject
    public var category: CategoryID
    public var safety: SafetyLevel
    public var size: SizeEstimate
    public var evidence: [Evidence]
    /// What it is and what happens if it's removed.
    public var explanation: String
    public var constraints: [Constraint]
    /// True only for regenerable items from trusted rules.
    public var preselected: Bool

    public init(
        id: String,
        subject: Subject,
        category: CategoryID,
        safety: SafetyLevel,
        size: SizeEstimate,
        evidence: [Evidence] = [],
        explanation: String,
        constraints: [Constraint] = [],
        preselected: Bool = false
    ) {
        self.id = id
        self.subject = subject
        self.category = category
        self.safety = safety
        self.size = size
        self.evidence = evidence
        self.explanation = explanation
        self.constraints = constraints
        // Only regenerable data may ever start selected.
        self.preselected = preselected && safety == .regenerable
    }
}
