import SwiftUI

/// Decorative contour lines. The data visualizations use their own scales and legends.
public struct Terrain: View {
    private let ink: Color
    private let center: UnitPoint

    public init(ink: Color, center: UnitPoint = .center) {
        self.ink = ink
        self.center = center
    }

    public var body: some View {
        Canvas { context, size in
            let unit = max(size.width * 0.58, size.height * 0.70)
            context.translateBy(x: center.x * size.width, y: center.y * size.height)
            for level in 1...30 {
                let scale = CGFloat(level) / 20
                var layer = context
                layer.translateBy(x: -unit * scale * 0.18, y: unit * scale * 0.10)
                layer.scaleBy(x: unit * scale, y: unit * scale * 0.78)
                layer.rotate(by: .degrees(Double(level) * 0.85 - 22))
                let major = level.isMultiple(of: 5)
                layer.stroke(Self.contour, with: .color(ink.opacity(major ? 0.8 : 0.46)),
                             lineWidth: (major ? 1.3 : 0.8) / (unit * scale))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static let contour: Path = {
        var path = Path()
        path.move(to: CGPoint(x: 0.97, y: -0.12))
        path.addCurve(to: CGPoint(x: 0.54, y: 0.60), control1: CGPoint(x: 1.08, y: 0.28), control2: CGPoint(x: 0.69, y: 0.32))
        path.addCurve(to: CGPoint(x: -0.18, y: 0.77), control1: CGPoint(x: 0.34, y: 0.95), control2: CGPoint(x: 0.11, y: 0.66))
        path.addCurve(to: CGPoint(x: -0.94, y: 0.22), control1: CGPoint(x: -0.56, y: 0.94), control2: CGPoint(x: -1.06, y: 0.58))
        path.addCurve(to: CGPoint(x: -0.62, y: -0.45), control1: CGPoint(x: -0.88, y: -0.04), control2: CGPoint(x: -0.60, y: -0.04))
        path.addCurve(to: CGPoint(x: -0.10, y: -0.78), control1: CGPoint(x: -0.64, y: -0.80), control2: CGPoint(x: -0.41, y: -0.99))
        path.addCurve(to: CGPoint(x: 0.97, y: -0.12), control1: CGPoint(x: 0.37, y: -0.45), control2: CGPoint(x: 0.79, y: -0.75))
        path.closeSubpath()
        return path
    }()
}

public struct SymbolTile: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    public init(_ symbol: String, tint: Color, size: CGFloat = 34) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.29))
            .accessibilityHidden(true)
    }
}
