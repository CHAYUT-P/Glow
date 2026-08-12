import AppKit
import SwiftUI

struct GlowSettings: Codable, Equatable {
    var fontSize: Double = 13
    var fontName: String = "System Mono"
    var themeName: String = "dark"
    var openLastLayoutOnLaunch = false
    var notifyOnCommandDone = true
    var globalHotkeyEnabled = true
}

struct GlowTheme {
    let name: String
    let background: NSColor
    let foreground: NSColor
    let caret: NSColor
    let selectionBackground: NSColor
    let selectionForeground: NSColor

    var colorScheme: ColorScheme { name == "light" ? .light : .dark }

    static let dark = GlowTheme(
        name: "dark",
        background: NSColor(srgbRed: 0.050, green: 0.067, blue: 0.090, alpha: 1),
        foreground: NSColor(srgbRed: 0.902, green: 0.929, blue: 0.953, alpha: 1),
        caret: NSColor(srgbRed: 0.941, green: 0.965, blue: 0.988, alpha: 1),
        selectionBackground: NSColor(srgbRed: 0.149, green: 0.310, blue: 0.471, alpha: 1),
        selectionForeground: NSColor.white
    )

    static let light = GlowTheme(
        name: "light",
        background: NSColor.white,
        foreground: NSColor(srgbRed: 0.141, green: 0.161, blue: 0.180, alpha: 1),
        caret: NSColor.black,
        selectionBackground: NSColor(srgbRed: 0.671, green: 0.808, blue: 0.969, alpha: 1),
        selectionForeground: NSColor.black
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

extension Color {
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
