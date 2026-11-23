import DesignSystem
import SwiftUI

/// One colored segment of a `DiskRingView`.
public struct RingSegment: Identifiable, Hashable {
    public let id: String
    public let value: Double
    public let color: Color
    /// Spoken by VoiceOver, for example "Installers, 14.6 GB".
    public let label: String

    public init(id: String, value: Double, color: Color, label: String) {
        self.id = id
        self.value = value
        self.color = color
        self.label = label
    }
}

/// A ring of colored segments with content in its center. Segments animate with springs
/// when their values change, so the ring grows as scan results stream in.
public struct DiskRingView<Center: View>: View {
    private let segments: [RingSegment]
    private let lineWidth: CGFloat
    private let center: Center

    public init(segments: [RingSegment], lineWidth: CGFloat = 26, @ViewBuilder center: () -> Center) {
        self.segments = segments
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        let slices = RingLayout.slices(for: segments.map { RingValue(id: $0.id, value: $0.value) })
        let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            ForEach(slices) { slice in
                RingArc(start: slice.start, end: slice.end)
                    .stroke(byID[slice.id]?.color.gradient ?? Color.gray.gradient,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .accessibilityElement()
                    .accessibilityLabel(byID[slice.id]?.label ?? "")
            }
            center
        }
        .padding(lineWidth / 2)
        .animation(Motion.smooth, value: slices)
        .accessibilityElement(children: .contain)
    }
}

/// An animatable arc between two fractions of a turn, starting at 12 o'clock.
struct RingArc: Shape {
    var start: Double
    var end: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(start, end) }
        set {
            start = newValue.first
            end = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(start * 360 - 90),
            endAngle: .degrees(end * 360 - 90),
            clockwise: false
        )
        return path
    }
}

/// An indeterminate ring shown while a scan has no totals yet.
public struct ScanningRingView<Center: View>: View {
    private let lineWidth: CGFloat
    private let center: Center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(lineWidth: CGFloat = 26, @ViewBuilder center: () -> Center) {
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            ZStack {
                Circle().stroke(.quaternary, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(
                        AngularGradient(colors: [Palette.accent.opacity(0), Palette.accent], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(108)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(reduceMotion ? 0 : turn * 360 - 90))
                center
            }
            .padding(lineWidth / 2)
        }
        .accessibilityLabel("Scanning")
    }
}
