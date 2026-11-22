import SwiftUI

/// Spacing on an 8-point grid.
public enum Spacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let hero: CGFloat = 48
}

/// Corner radii, always drawn with continuous curves.
public enum Radius {
    public static let control: CGFloat = 6
    public static let card: CGFloat = 12
    public static let panel: CGFloat = 18
}

/// Motion presets. No animation in the app runs longer than `cap`.
public enum Motion {
    /// Selection and small state changes.
    public static var snappy: Animation { .snappy(duration: 0.25) }
    /// Navigation and layout changes.
    public static var smooth: Animation { .smooth(duration: 0.45) }
    /// Celebration only.
    public static var bouncy: Animation { .bouncy(duration: 0.6) }
    /// Views entering the screen.
    public static var reveal: Animation { .easeOut(duration: 0.22) }
    public static let cap: Duration = .milliseconds(1200)
}

extension Font {
    /// Hero numbers, such as available space.
    public static var rakerHero: Font { .system(size: 44, weight: .semibold, design: .rounded) }
    /// Metrics in cards and legends.
    public static var rakerMetric: Font { .system(size: 22, weight: .semibold, design: .rounded) }
}
