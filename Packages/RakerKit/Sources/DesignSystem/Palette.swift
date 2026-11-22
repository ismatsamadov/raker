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
