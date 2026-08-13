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

/// Glow's themes are adapted from Warp's design system: a pure-black (or pure
/// white) terminal base, a single vivid cyan accent reused across every
/// interactive element, and UI chrome built as the base color plus a subtle
/// overlay + hairline outline.
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

    static let dark = GlowTheme(
        name: "dark",
        background: ns(0x000000),
        foreground: ns(0xFFFFFF),
        caret: ns(0x00C2FF),
        selectionBackground: ns(0x00C2FF, alpha: 0.35),
        selectionForeground: .white,
        accent: ns(0x00C2FF),
        chrome: ns(0x0D0D0D),
        separator: ns(0xFFFFFF, alpha: 0.08),
        ansi: [
            ansi(0x616161), ansi(0xFF8272), ansi(0xB4FA72), ansi(0xFEFDC2),
            ansi(0xA5D5FE), ansi(0xFF8FFD), ansi(0xD0D1FE), ansi(0xF1F1F1),
            ansi(0x8E8E8E), ansi(0xFFC4BD), ansi(0xD6FCB9), ansi(0xFEFDD5),
            ansi(0xC1E3FE), ansi(0xFFB1FE), ansi(0xE5E6FE), ansi(0xFEFFFF)
        ]
    )

    static let light = GlowTheme(
        name: "light",
        background: ns(0xFFFFFF),
        foreground: ns(0x111111),
        caret: ns(0x00C2FF),
        selectionBackground: ns(0x00C2FF, alpha: 0.35),
        selectionForeground: .black,
        accent: ns(0x00C2FF),
        chrome: ns(0xF6F6F6),
        separator: ns(0x000000, alpha: 0.08),
        ansi: [
            ansi(0x616161), ansi(0xFF8272), ansi(0xB4FA72), ansi(0xFEFDC2),
            ansi(0xA5D5FE), ansi(0xFF8FFD), ansi(0xD0D1FE), ansi(0xF1F1F1),
            ansi(0x8E8E8E), ansi(0xFFC4BD), ansi(0xD6FCB9), ansi(0xFEFDD5),
            ansi(0xC1E3FE), ansi(0xFFB1FE), ansi(0xE5E6FE), ansi(0xFEFFFF)
        ]
    )

    static func forName(_ name: String) -> GlowTheme {
        name == "light" ? light : dark
    }

    static let fontChoices = [
        "System Mono", "SF Mono", "Menlo", "Monaco", "JetBrains Mono", "Courier New"
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
