import Foundation

/// A finding staged for cleaning, and the section it was staged from.
public struct TrayItem: Codable, Sendable, Hashable, Identifiable {
    public enum Source: String, Codable, Sendable, CaseIterable {
        /// Caches, temporary files and logs.
        case cleanup
        case downloads
        case largeAndOld
        case duplicates
    }

    public var finding: Finding
    public var source: Source
    public var stagedAt: Date

    public var id: String { finding.id }

    public init(finding: Finding, source: Source, stagedAt: Date = .now) {
        self.finding = finding
        self.source = source
        self.stagedAt = stagedAt
    }
}

/// Items staged for cleaning from any section, in the order they were staged. Each
/// finding is in it at most once. Nothing in it is removed until the person reviews it.
public struct Tray: Sendable, Equatable {
    public private(set) var items: [TrayItem] = []
    /// IDs by section, so lists can ask about every row cheaply.
    private var idsBySource: [TrayItem.Source: Set<String>] = [:]
    private var sourceByID: [String: TrayItem.Source] = [:]

    public init(items: [TrayItem] = []) {
        for item in items {
            stage(item)
        }
    }

    public var isEmpty: Bool { items.isEmpty }
    public var count: Int { items.count }
    public var findings: [Finding] { items.map(\.finding) }

    public func contains(_ id: String) -> Bool {
        sourceByID[id] != nil
    }

    /// IDs of the findings staged from one section.
    public func ids(from source: TrayItem.Source) -> Set<String> {
        idsBySource[source] ?? []
    }

    public func items(from source: TrayItem.Source) -> [TrayItem] {
        items.filter { $0.source == source }
    }

    /// Adds an item. Staging a finding that's already in the Tray updates it in place.
    public mutating func stage(_ item: TrayItem) {
        if let previous = sourceByID[item.id] {
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].finding = item.finding
            items[index].source = item.source
            idsBySource[previous]?.remove(item.id)
        } else {
            items.append(item)
        }
        sourceByID[item.id] = item.source
        idsBySource[item.source, default: []].insert(item.id)
    }

    public mutating func unstage(_ id: String) {
        guard let source = sourceByID.removeValue(forKey: id) else { return }
        idsBySource[source]?.remove(id)
        items.removeAll { $0.id == id }
    }

    public mutating func unstage(where shouldRemove: (TrayItem) -> Bool) {
        var removed: [TrayItem] = []
        items.removeAll { item in
            guard shouldRemove(item) else { return false }
            removed.append(item)
            return true
        }
        for item in removed {
            sourceByID[item.id] = nil
            idsBySource[item.source]?.remove(item.id)
        }
    }

    public mutating func removeAll() {
        items = []
        idsBySource = [:]
        sourceByID = [:]
    }

    /// Space the staged items take on disk.
    public var allocatedBytes: UInt64 {
        items.reduce(0) { $0 &+ $1.finding.size.allocated }
    }

    /// Space removing them would free at least; data shared with clones or other files stays.
    public var reclaimableBytes: UInt64 {
        items.reduce(0) { $0 &+ ($1.finding.size.reclaimable ?? 0) }
    }

    public static func == (lhs: Tray, rhs: Tray) -> Bool {
        lhs.items == rhs.items
    }
}
