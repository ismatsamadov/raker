import Foundation

/// A rule the user set: a location Raker leaves alone, or originals it always keeps.
public struct UserRule: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// Raker never suggests or removes anything at or inside this path.
        case exclude
        /// Originals: always kept, for example as the copy that stays when they have duplicates.
        case lockOriginal
    }

    public var id: UUID
    public var path: String
    public var kind: Kind
    public var createdAt: Date

    public init(id: UUID = UUID(), path: String, kind: Kind, createdAt: Date = .now) {
        self.id = id
        self.path = path
        self.kind = kind
        self.createdAt = createdAt
    }
}

extension Array where Element == UserRule {
    /// Paths of `exclude` rules.
    public var exclusions: [String] { filter { $0.kind == .exclude }.map(\.path) }

    /// Paths of `lockOriginal` rules.
    public var lockedOriginals: [String] { filter { $0.kind == .lockOriginal }.map(\.path) }
}
