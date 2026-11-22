import Testing
@testable import VisualizationKit

@Suite("RingLayout")
struct RingLayoutTests {
    @Test("Slices are proportional, ordered and separated by gaps")
    func proportionalSlices() throws {
        let slices = RingLayout.slices(
            for: [RingValue(id: "a", value: 3), RingValue(id: "b", value: 1)],
            gap: 0.01, minimumSpan: 0
        )
        try #require(slices.count == 2)
        #expect(slices.map(\.id) == ["a", "b"])
        #expect(abs(slices[0].span / slices[1].span - 3) < 1e-9)
        #expect(abs(slices[1].start - slices[0].end - 0.01) < 1e-9)
        // Slices plus gaps make exactly one turn.
        #expect(abs(slices.reduce(0) { $0 + $1.span } + 0.02 - 1) < 1e-9)
    }

    @Test("Tiny values stay visible")
    func minimumSpan() {
        let slices = RingLayout.slices(
            for: [RingValue(id: "big", value: 1_000_000), RingValue(id: "tiny", value: 1)],
            gap: 0, minimumSpan: 0.02
        )
        #expect(slices.last.map { $0.span >= 0.019 } == true)
    }

    @Test("Zero, negative and non-finite values are skipped")
    func invalidValues() {
        let slices = RingLayout.slices(for: [
            RingValue(id: "zero", value: 0),
            RingValue(id: "negative", value: -5),
            RingValue(id: "nan", value: .nan),
            RingValue(id: "only", value: 2),
        ])
        #expect(slices.map(\.id) == ["only"])
        #expect(slices.first.map { abs($0.span - 1) < 1e-9 } == true)
        #expect(RingLayout.slices(for: []).isEmpty)
    }
}
