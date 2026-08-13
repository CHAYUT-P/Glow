import AppKit
import SwiftTerm
import SwiftUI

struct GlowSettings: Codable, Equatable {
    var fontSize: Double = 13
    var fontName: String = "System Mono"
    var themeName: String = "dark"
    var openLastLayoutOnLaunch = false
    var notifyOnCommandDone = true
    var globalHotkeyEnabled = true
}

/// Glow's themes follow the ThoughtStream design system: a warm, flat,
/// reading-first palette with a single stone accent, hairline borders instead
/// of shadows, and sharp (0px) edges everywhere.
struct GlowTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor
    let accent: NSColor
    let chrome: NSColor
    let separator: NSColor
    let ansi: [SwiftTerm.Color]

    var colorScheme: ColorScheme { name == "light" ? .light : .dark }

    private static func ns(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    private static func ansi(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(red8: UInt16((hex >> 16) & 0xFF),
                        green8: UInt16((hex >> 8) & 0xFF),
                        blue8: UInt16(hex & 0xFF))
    }

    /// ThoughtStream light: warm white page, warm black text, stone accent.
    static let light = GlowTheme(
        name: "light",
        background: ns(0xFAFAF9),
        foreground: ns(0x1C1917),
        caret: ns(0x78716C),
        selectionBackground: ns(0x78716C, alpha: 0.30),
        selectionForeground: ns(0x1C1917),
        accent: ns(0x78716C),
        chrome: ns(0xF5F5F4),
        separator: ns(0xE7E5E4),
        ansi: [
            ansi(0x292524), ansi(0xB91C1C), ansi(0x4D7C0F), ansi(0xA16207),
            ansi(0x4F6E8F), ansi(0x9D6B8E), ansi(0x3E8A84), ansi(0xD6D3D1),
            ansi(0x57534E), ansi(0xDC2626), ansi(0x65A30D), ansi(0xCA8A04),
            ansi(0x6E8FB5), ansi(0xB0779E), ansi(0x5FA8A0), ansi(0xFAFAF9)
        ]
    )

    /// ThoughtStream dark: warm black page, warm white text, sage accent.
    static let dark = GlowTheme(
        name: "dark",
        background: ns(0x1C1917),
        foreground: ns(0xFAFAF9),
        caret: ns(0xA8A29E),
        selectionBackground: ns(0xA8A29E, alpha: 0.30),
        selectionForeground: ns(0xFAFAF9),
        accent: ns(0xA8A29E),
        chrome: ns(0x292524),
        separator: ns(0x44403C),
        ansi: [
            ansi(0x292524), ansi(0xB91C1C), ansi(0x4D7C0F), ansi(0xA16207),
            ansi(0x4F6E8F), ansi(0x9D6B8E), ansi(0x3E8A84), ansi(0xD6D3D1),
            ansi(0x57534E), ansi(0xDC2626), ansi(0x65A30D), ansi(0xCA8A04),
            ansi(0x6E8FB5), ansi(0xB0779E), ansi(0x5FA8A0), ansi(0xFAFAF9)
        ]
    )

    static func forName(_ name: String) -> GlowTheme {
        name == "light" ? light : dark
    }

    static let fontChoices = [
        "System Mono", "SF Mono", "Menlo", "Monaco", "Source Code Pro", "Fira Code", "Courier New"
    ]

    static func makeFont(name: String, size: Double) -> NSFont {
        if name == "System Mono" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: name, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static let tabColors: [(hex: String, name: String)] = [
        ("E5484D", "Red"),
        ("F76B15", "Orange"),
        ("FFB224", "Amber"),
        ("46A758", "Green"),
        ("30A46C", "Teal"),
        ("0090FF", "Blue"),
        ("5E5CE6", "Indigo"),
        ("8E4EC6", "Purple"),
        ("E93D82", "Pink"),
        ("ADB5BD", "Gray")
    ]

    static func colorName(_ hex: String) -> String {
        tabColors.first { $0.hex == hex }?.name ?? "Custom"
    }
}

extension SwiftUI.Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
