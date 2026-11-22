import Foundation

/// Where a finding goes when a plan runs.
public enum Destination: Codable, Sendable, Hashable {
    /// The default for anything that isn't regenerable.
    case trash
    /// Regenerable data only, after explicit consent.
    case delete
    /// For example, setting duplicates aside in a folder.
    case move(to: String)
    /// iCloud Drive: keep the cloud copy, free the local one.
    case removeDownload
    /// A typed maintenance or developer action.
    case action(id: String)
}

public struct PlanItem: Codable, Sendable, Hashable {
    public var finding: Finding
    public var destination: Destination

    public init(finding: Finding, destination: Destination) {
        self.finding = finding
        self.destination = destination
    }
}

/// The only way anything gets removed: a reviewed, validated, immutable list of items.
public struct CleanupPlan: Codable, Sendable, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let items: [PlanItem]
    /// Measured when the plan is created, so the receipt can report the observed change.
    public let spaceBefore: VolumeSpace?

    public init(id: UUID = UUID(), createdAt: Date = .now, items: [PlanItem], spaceBefore: VolumeSpace?) {
        self.id = id
        self.createdAt = createdAt
        self.items = items
        self.spaceBefore = spaceBefore
    }
}
