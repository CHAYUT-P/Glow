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

/// Glow's themes follow a flat, reading-first palette: warm neutrals, a single
/// accent, hairline borders instead of shadows, and sharp (0px) edges.
/// Each theme pairs a terminal palette (background/foreground/caret/selection/
/// ANSI) with chrome colors (window chrome, separators, accent) so the whole
/// window shifts tone together.
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

    var colorScheme: ColorScheme { Self.lightSchemes.contains(name) ? .light : .dark }
    var displayName: String {
        switch name {
        case "darker": return "Darker Dark"
        case "rawblock": return "RawBlock"
        default: return name.capitalized
        }
    }

    private static let lightSchemes = ["light", "sepia"]

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

    /// Deeper black: near-void page, cooler neutrals, for OLED-style contrast.
    static let darker = GlowTheme(
        name: "darker",
        background: ns(0x050505),
        foreground: ns(0xF2F2F0),
        caret: ns(0x9E9E9E),
        selectionBackground: ns(0x9E9E9E, alpha: 0.30),
        selectionForeground: ns(0xF2F2F0),
        accent: ns(0x9E9E9E),
        chrome: ns(0x0D0D0D),
        separator: ns(0x262626),
        ansi: [
            ansi(0x0A0A0A), ansi(0xB31E1E), ansi(0x4A7512), ansi(0x9C5F08),
            ansi(0x4A6684), ansi(0x926288), ansi(0x3A7F7A), ansi(0xC9C9C9),
            ansi(0x505050), ansi(0xD02222), ansi(0x5F9C10), ansi(0xBE8406),
            ansi(0x6484A8), ansi(0xA47092), ansi(0x589C96), ansi(0xEDEDED)
        ]
    )

    /// Earth: warm clay, sand, ochre and olive on a deep umber page.
    static let earth = GlowTheme(
        name: "earth",
        background: ns(0x292118),
        foreground: ns(0xE6DCC3),
        caret: ns(0xC2B28F),
        selectionBackground: ns(0xC2B28F, alpha: 0.30),
        selectionForeground: ns(0x292118),
        accent: ns(0xB08968),
        chrome: ns(0x33291D),
        separator: ns(0x4A3D2B),
        ansi: [
            ansi(0x1F1812), ansi(0xA34A2A), ansi(0x6E7F3E), ansi(0xB9852F),
            ansi(0x5F7A8C), ansi(0x8A5A44), ansi(0x4F7A68), ansi(0xD9CDB4),
            ansi(0x6B5F4C), ansi(0xC25E33), ansi(0x8FA055), ansi(0xD9A23F),
            ansi(0x7E9FB5), ansi(0xA9785E), ansi(0x6E9A85), ansi(0xF0E8D4)
        ]
    )

    /// RawBlock: the brutalist system — pure black page, pure white chrome,
    /// link-blue accent, and the system's raw error/warning/success colors.
    static let rawblock = GlowTheme(
        name: "rawblock",
        background: ns(0x000000),
        foreground: ns(0xFFFFFF),
        caret: ns(0xFFFFFF),
        selectionBackground: ns(0xFFFFFF, alpha: 0.30),
        selectionForeground: ns(0x000000),
        accent: ns(0x0000FF),
        chrome: ns(0x000000),
        separator: ns(0xFFFFFF),
        ansi: [
            ansi(0x000000), ansi(0xFF0000), ansi(0x008000), ansi(0xFFA500),
            ansi(0x0000FF), ansi(0xFF00FF), ansi(0x00FFFF), ansi(0xFFFFFF),
            ansi(0x808080), ansi(0xFF0000), ansi(0x008000), ansi(0xFFA500),
            ansi(0x0000FF), ansi(0xFF00FF), ansi(0x00FFFF), ansi(0xFFFFFF)
        ]
    )

    /// Midnight: cool navy page, pale blue text, slate accents.
    static let midnight = GlowTheme(
        name: "midnight",
        background: ns(0x0A0F1E),
        foreground: ns(0xD6E0F0),
        caret: ns(0x9FB4D4),
        selectionBackground: ns(0x9FB4D4, alpha: 0.30),
        selectionForeground: ns(0x0A0F1E),
        accent: ns(0x7CA3D6),
        chrome: ns(0x121829),
        separator: ns(0x243047),
        ansi: [
            ansi(0x10182A), ansi(0xC0504D), ansi(0x5E8C61), ansi(0xC9A34E),
            ansi(0x6E8FB5), ansi(0xA07CB8), ansi(0x58A6A0), ansi(0xD8E1F2),
            ansi(0x4A5670), ansi(0xE06560), ansi(0x74AC78), ansi(0xE0B95C),
            ansi(0x86A9D0), ansi(0xB98FD0), ansi(0x6EBDB6), ansi(0xEAF1FC)
        ]
    )

    /// Sepia: aged paper page, ink-brown text, warm tan accents.
    static let sepia = GlowTheme(
        name: "sepia",
        background: ns(0xF4E9D2),
        foreground: ns(0x40382A),
        caret: ns(0x7A6C52),
        selectionBackground: ns(0x7A6C52, alpha: 0.30),
        selectionForeground: ns(0x40382A),
        accent: ns(0x8A6D4B),
        chrome: ns(0xEDE2CB),
        separator: ns(0xD6C7A4),
        ansi: [
            ansi(0x574B38), ansi(0x9E4A3C), ansi(0x5F7A45), ansi(0x9C7A2E),
            ansi(0x4E6A8C), ansi(0x8A5F78), ansi(0x3E7A6C), ansi(0xE8DCC0),
            ansi(0x8A7A5C), ansi(0xC05C48), ansi(0x74905A), ansi(0xB8933C),
            ansi(0x6484AC), ansi(0xA87394), ansi(0x559488), ansi(0xF7EFDC)
        ]
    )

    /// Moss: deep forest page, pale green text, leafy accents.
    static let moss = GlowTheme(
        name: "moss",
        background: ns(0x0F150C),
        foreground: ns(0xD9E4C8),
        caret: ns(0xA6BC8C),
        selectionBackground: ns(0xA6BC8C, alpha: 0.30),
        selectionForeground: ns(0x0F150C),
        accent: ns(0x8FAF63),
        chrome: ns(0x181F12),
        separator: ns(0x2A3420),
        ansi: [
            ansi(0x131A0E), ansi(0xB04938), ansi(0x5F8A3E), ansi(0xA8832E),
            ansi(0x4F7090), ansi(0x8A5E7E), ansi(0x3F8270), ansi(0xCBD8B8),
            ansi(0x55643F), ansi(0xCE5E48), ansi(0x74A84E), ansi(0xC49A38),
            ansi(0x6488AC), ansi(0xA87496), ansi(0x529A84), ansi(0xE8F0DC)
        ]
    )

    /// Grok: the Grok Build TUI's GrokNight palette — neutral `#141414`
    /// base, light gray text, and TokyoNight's violet-magenta accent.
    static let grok = GlowTheme(
        name: "grok",
        background: ns(0x141414),
        foreground: ns(0xE1E1E1),
        caret: ns(0xC8C8C8),
        selectionBackground: ns(0xC8C8C8, alpha: 0.30),
        selectionForeground: ns(0x141414),
        accent: ns(0xBB9AF7),
        chrome: ns(0x1C1C1C),
        separator: ns(0x323237),
        ansi: [
            ansi(0x161616), ansi(0xF7768E), ansi(0x9ECE6A), ansi(0xE0AF68),
            ansi(0x7AA2F7), ansi(0xBB9AF7), ansi(0x7DCFFF), ansi(0xC8C8C8),
            ansi(0x585858), ansi(0xDB4B4B), ansi(0x73DACA), ansi(0xFF9E64),
            ansi(0x3D59A1), ansi(0x9D7CD8), ansi(0x1ABC9C), ansi(0xE1E1E1)
        ]
    )

    static let all: [GlowTheme] = [dark, light, darker, earth, rawblock, midnight, sepia, moss, grok]

    static func forName(_ name: String) -> GlowTheme {
        switch name {
        case "light": return light
        case "darker": return darker
        case "earth": return earth
        case "rawblock": return rawblock
        case "midnight": return midnight
        case "sepia": return sepia
        case "moss": return moss
        case "grok": return grok
        default: return dark
        }
    }

    static let fontChoices = [
        "System Mono", "SF Mono", "Menlo", "Monaco", "Source Code Pro", "Fira Code", "Space Mono", "Courier New"
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
