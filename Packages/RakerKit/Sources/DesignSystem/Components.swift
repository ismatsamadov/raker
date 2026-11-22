import RakerFoundation
import SwiftUI

/// A byte count that rolls smoothly to new values, like Finder-formatted totals.
public struct SizeText: View {
    private let bytes: UInt64

    public init(_ bytes: UInt64) {
        self.bytes = bytes
    }

    public var body: some View {
        Text(ByteCount(bytes).formatted)
            .monospacedDigit()
            .contentTransition(.numericText(value: Double(bytes)))
    }
}

/// A thin proportional bar used next to sizes in lists.
public struct SizeBar: View {
    private let fraction: Double
    private let tint: Color

    public init(fraction: Double, tint: Color = .accentColor) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient)
                    .frame(width: max(proxy.size.width * fraction, fraction > 0 ? 3 : 0))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Glass on macOS 26 and later, vibrancy material before. For controls and floating
/// layers only, never behind content.
public struct GlassPanel: ViewModifier {
    let cornerRadius: CGFloat

    public func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            materialFallback(content)
        }
        #else
        materialFallback(content)
        #endif
    }

    private func materialFallback(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// An opaque card for content such as insights and summaries.
public struct SurfaceCard: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(Palette.paper))
            .overlay(shape.strokeBorder(Palette.rule.opacity(contrast == .increased ? 1 : 0.8), lineWidth: contrast == .increased ? 1.5 : 0.75))
    }
}

extension View {
    public func glassPanel(cornerRadius: CGFloat = Radius.panel) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }

    public func surfaceCard(cornerRadius: CGFloat = Radius.card) -> some View {
        modifier(SurfaceCard(cornerRadius: cornerRadius))
    }

    /// The prominent style for a screen's primary action: glass on macOS 26 and later.
    @ViewBuilder
    public func prominentActionStyle() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
        #else
        buttonStyle(.borderedProminent)
        #endif
    }
}
