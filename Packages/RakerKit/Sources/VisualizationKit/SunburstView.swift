import DesignSystem
import SwiftUI

/// Rings of sectors around a center. When the layout changes, such as when zooming into a
/// folder, segments morph to their new angles and rings.
public struct SunburstView<ID: Hashable & Sendable, Center: View>: View {
    private let segments: [SunburstSegment<ID>]
    private let rings: Int
    private let highlighted: Set<SunburstSegment<ID>.Key>
    private let color: (SunburstSegment<ID>) -> Color
    private let label: (SunburstSegment<ID>) -> String
    private let onHover: (SunburstSegment<ID>.Key?) -> Void
    private let onSelect: (SunburstSegment<ID>) -> Void
    private let center: Center

    /// - Parameters:
    ///   - highlighted: Segments to emphasize, such as the hovered one and its ancestors;
    ///     the others fade while it isn't empty.
    ///   - label: Spoken by VoiceOver, for example "Movies, 128 GB, 31 percent".
    public init(
        segments: [SunburstSegment<ID>],
        rings: Int = 5,
        highlighted: Set<SunburstSegment<ID>.Key> = [],
        color: @escaping (SunburstSegment<ID>) -> Color,
        label: @escaping (SunburstSegment<ID>) -> String,
        onHover: @escaping (SunburstSegment<ID>.Key?) -> Void = { _ in },
        onSelect: @escaping (SunburstSegment<ID>) -> Void,
        @ViewBuilder center: () -> Center
    ) {
        self.segments = segments
        self.rings = rings
        self.highlighted = highlighted
        self.color = color
        self.label = label
        self.onHover = onHover
        self.onSelect = onSelect
        self.center = center()
    }

    /// The center's share of the radius.
    private let hole = 0.3

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                ForEach(segments) { segment in
                    sector(for: segment)
                }
                center
                    .frame(width: side * hole * 0.9, height: side * hole * 0.9)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .animation(Motion.smooth, value: segments)
        .animation(Motion.snappy, value: highlighted)
        .accessibilityElement(children: .contain)
    }

    private func sector(for segment: SunburstSegment<ID>) -> some View {
        let ringWidth = (1 - hole) / Double(max(rings, 1))
        let inner = hole + ringWidth * Double(segment.depth - 1)
        let shape = AnnularSector(start: segment.start, end: segment.end, inner: inner, outer: inner + ringWidth)
        return shape
            .fill(color(segment).opacity(highlighted.isEmpty || highlighted.contains(segment.key) ? 1 : 0.4))
            // Gaps between segments in the color of the canvas the lens sits on.
            .overlay(shape.stroke(Palette.canvas, lineWidth: 1))
            .contentShape(shape)
            .onHover { inside in
                if inside {
                    onHover(segment.key)
                } else if highlighted.contains(segment.key) {
                    onHover(nil)
                }
            }
            .onTapGesture { onSelect(segment) }
            .accessibilityElement()
            .accessibilityLabel(label(segment))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onSelect(segment) }
    }
}

/// A piece of a ring between two angles and two radii. Angles are fractions of a turn from
/// 12 o'clock; radii are fractions of the largest circle that fits.
struct AnnularSector: Shape {
    var start: Double
    var end: Double
    var inner: Double
    var outer: Double

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { AnimatablePair(AnimatablePair(start, end), AnimatablePair(inner, outer)) }
        set {
            start = newValue.first.first
            end = newValue.first.second
            inner = newValue.second.first
            outer = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let from = Angle.degrees(start * 360 - 90)
        let to = Angle.degrees(end * 360 - 90)
        var path = Path()
        path.addArc(center: center, radius: radius * outer, startAngle: from, endAngle: to, clockwise: false)
        path.addArc(center: center, radius: radius * inner, startAngle: to, endAngle: from, clockwise: true)
        path.closeSubpath()
        return path
    }
}
