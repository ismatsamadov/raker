/// One value to show on a ring.
public struct RingValue: Hashable, Sendable {
    public var id: String
    public var value: Double

    public init(id: String, value: Double) {
        self.id = id
        self.value = value
    }
}

/// A slice of a ring, as fractions of a full turn starting at 12 o'clock.
public struct RingSlice: Identifiable, Hashable, Sendable {
    public let id: String
    public let start: Double
    public let end: Double

    public var span: Double { end - start }
}

/// Pure ring geometry, kept separate from drawing so it can be tested and computed off
/// the main thread.
public enum RingLayout {
    /// Lays out positive values around a ring in the given order.
    ///
    /// - Parameters:
    ///   - gap: Space between neighboring slices, as a fraction of a turn.
    ///   - minimumSpan: Smallest slice drawn, so tiny categories stay visible.
    public static func slices(for values: [RingValue], gap: Double = 0.006, minimumSpan: Double = 0.012) -> [RingSlice] {
        let visible = values.filter { $0.value > 0 && $0.value.isFinite }
        guard !visible.isEmpty else { return [] }
        let total = visible.reduce(0) { $0 + $1.value }
        let gapSize = visible.count > 1 ? gap : 0
        let available = max(0, 1 - gapSize * Double(visible.count))
        let spans = visible.map { max($0.value / total, minimumSpan) }
        let scale = available / spans.reduce(0, +)

        var slices: [RingSlice] = []
        slices.reserveCapacity(visible.count)
        var cursor = gapSize / 2
        for (item, span) in zip(visible, spans) {
            let length = span * scale
            slices.append(RingSlice(id: item.id, start: cursor, end: cursor + length))
            cursor += length + gapSize
        }
        return slices
    }
}
