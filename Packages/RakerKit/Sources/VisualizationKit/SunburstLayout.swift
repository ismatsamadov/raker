/// One segment of a sunburst: an item of a tree, drawn as part of a ring.
public struct SunburstSegment<ID: Hashable & Sendable>: Identifiable, Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        case item(ID)
        /// Items too narrow to draw on their own, merged into one segment per parent.
        case smaller(parent: ID)
    }

    public let key: Key
    /// The ring, counting out from the center: 1 is the innermost.
    public let depth: Int
    /// Fractions of a full turn, starting at 12 o'clock.
    public let start: Double
    public let end: Double
    public let value: Double
    /// Which first-ring segment this one descends from, so a branch can share a color.
    public let branch: Int

    public var id: Key { key }
    public var span: Double { end - start }
}

/// Pure sunburst geometry, kept apart from drawing so it can be tested.
public enum SunburstLayout {
    /// Lays out a tree in rings around `root`, which fills the center.
    ///
    /// - Parameters:
    ///   - children: An item's children, largest first.
    ///   - maxDepth: How many rings to draw.
    ///   - minimumSpan: Items narrower than this, as a fraction of a turn, merge into one
    ///     "smaller items" segment, which keeps the number of segments small for any tree.
    public static func segments<ID: Hashable & Sendable>(
        root: ID,
        value: (ID) -> Double,
        children: (ID) -> [ID],
        maxDepth: Int = 5,
        minimumSpan: Double = 0.5 / 360
    ) -> [SunburstSegment<ID>] {
        var segments: [SunburstSegment<ID>] = []
        var branches = 0

        func layOut(_ parent: ID, start: Double, span: Double, depth: Int, branch: Int?) {
            guard depth <= maxDepth else { return }
            let total = value(parent)
            guard total > 0, span > 0 else { return }
            var cursor = start
            var smallerValue = 0.0
            var smallerSpan = 0.0
            for child in children(parent) {
                let childValue = value(child)
                guard childValue > 0 else { continue }
                let childSpan = span * childValue / total
                if childSpan < minimumSpan {
                    smallerValue += childValue
                    smallerSpan += childSpan
                    continue
                }
                let childBranch = branch ?? { defer { branches += 1 }; return branches }()
                segments.append(SunburstSegment(key: .item(child), depth: depth, start: cursor, end: cursor + childSpan,
                                                value: childValue, branch: childBranch))
                layOut(child, start: cursor, span: childSpan, depth: depth + 1, branch: childBranch)
                cursor += childSpan
            }
            if smallerSpan > 0 {
                segments.append(SunburstSegment(key: .smaller(parent: parent), depth: depth, start: cursor,
                                                end: cursor + smallerSpan, value: smallerValue, branch: branch ?? -1))
            }
        }

        layOut(root, start: 0, span: 1, depth: 1, branch: nil)
        return segments
    }
}
