import SwiftUI

/// The same vector artwork is used in the app and rendered into the Finder icon.
public struct RakerIcon: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            context.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
            context.scaleBy(x: side / 100, y: side / 100)
            let tile = Path(roundedRect: CGRect(x: 5, y: 5, width: 90, height: 90),
                            cornerRadius: 21, style: .continuous)
            context.fill(tile, with: .linearGradient(
                Gradient(colors: [Color(red: 0.24, green: 0.39, blue: 0.28),
                                  Color(red: 0.065, green: 0.15, blue: 0.12)]),
                startPoint: CGPoint(x: 12, y: 5), endPoint: CGPoint(x: 77, y: 93)))
            context.stroke(tile, with: .color(.white.opacity(0.18)), lineWidth: 0.8)
            context.translateBy(x: 50, y: 50)
            context.rotate(by: .degrees(38))
            var rake = Path()
            rake.move(to: CGPoint(x: -17, y: -24))
            rake.addLine(to: CGPoint(x: -17, y: -9))
            rake.addQuadCurve(to: CGPoint(x: -10, y: -2), control: CGPoint(x: -17, y: -2))
            rake.addLine(to: CGPoint(x: 10, y: -2))
            rake.addQuadCurve(to: CGPoint(x: 17, y: -9), control: CGPoint(x: 17, y: -2))
            rake.addLine(to: CGPoint(x: 17, y: -24))
            rake.move(to: CGPoint(x: 0, y: -24))
            rake.addLine(to: CGPoint(x: 0, y: 28))
            context.stroke(rake, with: .color(Color(red: 0.88, green: 0.97, blue: 0.61)),
                           style: StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
