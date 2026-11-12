import AppKit
import SwiftUI

/// "Mono" design tokens: white (black in dark mode), black type, hairlines,
/// and a single red accent used only as a signal.
enum Theme {
    static let background = dynamic(light: 0xFFFFFF, dark: 0x000000)
    static let surface = dynamic(light: 0xF4F4F4, dark: 0x121212)
    static let hairline = dynamic(light: 0xE5E5E5, dark: 0x262626)
    static let primary = dynamic(light: 0x000000, dark: 0xFFFFFF)
    /// Secondary text: ≥ 4.5:1 contrast on the background in both modes.
    static let secondary = dynamic(light: 0x6B6B6B, dark: 0x9A9A9A)
    /// Decorative only (never for text that must be read).
    static let tertiary = dynamic(light: 0xBDBDBD, dark: 0x4A4A4A)
    static let onPrimary = dynamic(light: 0xFFFFFF, dark: 0x000000)
    /// Signal red: active state, Review, warnings, permanent deletion.
    static let accent = dynamic(light: 0xD71921, dark: 0xFF4040)
    static let dotOff = dynamic(light: 0xDEDEDE, dark: 0x2C2C2C)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

enum Typo {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static let title = Font.system(size: 30, weight: .light)
    static let body = Font.system(size: 13)
    static let bodyMedium = Font.system(size: 13, weight: .medium)
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
