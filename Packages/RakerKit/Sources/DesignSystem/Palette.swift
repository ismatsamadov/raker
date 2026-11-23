import AppKit
import SwiftUI

/// Semantic colors. Categories and safety levels come from system colors, so macOS handles
/// their light, dark and Increase Contrast variants.
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

/// Raker's own colors, with light and dark versions and stronger ones for Increase Contrast.
extension Palette {
    public static let forest = Color(red: 0.095, green: 0.175, blue: 0.145)
    public static let lichen = Color(red: 0.87, green: 0.96, blue: 0.63)

    /// The tint behind white labels on prominent buttons and checkboxes, so in dark mode it
    /// stays deep enough for them (4.7:1) while still standing out on the canvas (3.7:1).
    public static let accent = adaptive(light: 0x365F48, dark: 0x44805B, increasedLight: 0x24432F)
    public static let canvas = adaptive(light: 0xF3F4EE, dark: 0x171C19, increasedDark: 0x101411)
    public static let paper = adaptive(light: 0xFDFDF9, dark: 0x232A25, increasedLight: 0xFFFFFF)
    public static let rule = adaptive(light: 0xC9CEC3, dark: 0x535E54, increasedLight: 0x7E8778, increasedDark: 0x8F9A8F)
    public static let moss = adaptive(light: 0x506C39, dark: 0xBED68F, increasedLight: 0x384D27, increasedDark: 0xD7EAB2)
    public static let ochre = adaptive(light: 0x91602B, dark: 0xE7B573, increasedLight: 0x6A441B, increasedDark: 0xF5D3A1)
    public static let lagoon = adaptive(light: 0x316B73, dark: 0x8EC8CF, increasedLight: 0x214F56, increasedDark: 0xBCE5EA)
    public static let iris = adaptive(light: 0x695885, dark: 0xC6B5E0, increasedLight: 0x4B3D63, increasedDark: 0xDED3F0)

    /// - Parameters:
    ///   - increasedLight: Used in light mode with Increase Contrast on; `light` if nil.
    ///   - increasedDark: Used in dark mode with Increase Contrast on; `dark` if nil.
    private static func adaptive(light: UInt32, dark: UInt32, increasedLight: UInt32? = nil, increasedDark: UInt32? = nil) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            // High-contrast names first, ahead of the plain ones they fall back to.
            let match = appearance.bestMatch(from: [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua, .aqua, .darkAqua])
            let rgb = switch match ?? .aqua {
            case .darkAqua: dark
            case .accessibilityHighContrastAqua: increasedLight ?? light
            case .accessibilityHighContrastDarkAqua: increasedDark ?? dark
            default: light
            }
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
}
