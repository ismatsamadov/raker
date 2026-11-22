import Testing
@testable import VisualizationKit

/// root 100: a 50 (a1 30, a2 20), b 30, c 19.9, d 0.1
private let values: [String: Double] = ["root": 100, "a": 50, "a1": 30, "a2": 20, "b": 30, "c": 19.9, "d": 0.1]
private let tree: [String: [String]] = ["root": ["a", "b", "c", "d"], "a": ["a1", "a2"]]

private func layout(maxDepth: Int = 5) -> [SunburstSegment<String>] {
    SunburstLayout.segments(root: "root", value: { values[$0] ?? 0 }, children: { tree[$0] ?? [] }, maxDepth: maxDepth)
}

@Suite("SunburstLayout")
struct SunburstLayoutTests {
    @Test("Gives each item a share of its parent's arc, one ring further out")
    func rings() throws {
        let segments = layout()
        let byKey = Dictionary(uniqueKeysWithValues: segments.map { ($0.key, $0) })

        let a = try #require(byKey[.item("a")])
        #expect(a.depth == 1 && a.start == 0 && abs(a.end - 0.5) < 1e-9)
        let b = try #require(byKey[.item("b")])
        #expect(abs(b.start - 0.5) < 1e-9 && abs(b.end - 0.8) < 1e-9)
        let a2 = try #require(byKey[.item("a2")])
        #expect(a2.depth == 2 && abs(a2.start - 0.3) < 1e-9 && abs(a2.end - 0.5) < 1e-9)
        // Children share their first-ring ancestor's branch.
        #expect(a2.branch == a.branch)
        #expect(b.branch != a.branch)
    }

    @Test("Merges items too narrow to see into one segment per parent")
    func smallerItems() throws {
        let segments = layout()
        #expect(!segments.contains { $0.key == .item("d") })
        let smaller = try #require(segments.first { $0.key == .smaller(parent: "root") })
        #expect(smaller.depth == 1)
        #expect(abs(smaller.value - 0.1) < 1e-9)
        #expect(abs(smaller.end - 1) < 1e-9)
    }

    @Test("Stops at the outermost ring, and draws nothing for an empty tree")
    func limits() {
        #expect(layout(maxDepth: 1).allSatisfy { $0.depth == 1 })
        #expect(layout(maxDepth: 1).count == 4)
        #expect(SunburstLayout.segments(root: "x", value: { _ in 0 }, children: { _ in [] }).isEmpty)
    }
}
