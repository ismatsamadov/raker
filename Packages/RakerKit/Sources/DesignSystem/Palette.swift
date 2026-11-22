import AppKit
import SwiftUI

/// Semantic colors. They come from system colors, so light, dark and Increase Contrast
/// variants are handled by macOS.
public enum Palette {
    // Categories
    public static var apps: Color { Color(nsColor: .systemIndigo) }
    public static var installers: Color { Color(nsColor: .systemOrange) }
    public static var archives: Color { Color(nsColor: .systemTeal) }
    public static var media: Color { Color(nsColor: .systemPink) }
    public static var documents: Color { Color(nsColor: .systemBlue) }
    public static var developer: Color { Color(nsColor: .systemPurple) }
    public static var caches: Color { Color(nsColor: .systemMint) }
    public static var system: Color { Color(nsColor: .systemGray) }
    public static var other: Color { Color(nsColor: .systemBrown) }

    // Safety levels; always paired with an icon and a label, never color alone.
    public static var rebuildsAutomatically: Color { Color(nsColor: .systemGreen) }
    public static var review: Color { Color(nsColor: .systemBlue) }
    public static var expert: Color { Color(nsColor: .systemOrange) }
}

extension Palette {
    public static let forest = Color(red: 0.095, green: 0.175, blue: 0.145)
    public static let lichen = Color(red: 0.87, green: 0.96, blue: 0.63)

    public static let accent = adaptive(light: 0x365F48, dark: 0xA9D2AD)
    public static let canvas = adaptive(light: 0xF3F4EE, dark: 0x171C19)
    public static let paper = adaptive(light: 0xFDFDF9, dark: 0x232A25)
    public static let rule = adaptive(light: 0xC9CEC3, dark: 0x535E54)
    public static let moss = adaptive(light: 0x506C39, dark: 0xBED68F)
    public static let ochre = adaptive(light: 0x91602B, dark: 0xE7B573)
    public static let lagoon = adaptive(light: 0x316B73, dark: 0x8EC8CF)
    public static let iris = adaptive(light: 0x695885, dark: 0xC6B5E0)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}
