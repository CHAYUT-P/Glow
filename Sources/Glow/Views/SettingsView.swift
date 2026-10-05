import SwiftUI

struct SettingsView: View {
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 560)
        .tint(Color(nsColor: appModel.theme.accent))
    }
}

/// Theme gallery (each card is a miniature terminal in that theme), font
/// controls, and a live preview of the current choice.
private struct AppearanceSettings: View {
    @ObservedObject private var appModel = AppModel.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme")
                .font(.system(size: 12, weight: .semibold))
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(GlowTheme.all, id: \.name) { theme in
                    ThemeCard(theme: theme, selected: theme.name == appModel.settings.themeName) {
                        appModel.settings.themeName = theme.name
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Picker("Font", selection: $appModel.settings.fontName) {
                    ForEach(GlowTheme.fontChoices, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .frame(maxWidth: 220)
                Text("Size")
                Slider(value: $appModel.settings.fontSize, in: 8...24, step: 1)
                Text("\(Int(appModel.settings.fontSize))")
                    .font(.system(size: 12).monospacedDigit())
                    .frame(width: 24, alignment: .trailing)
            }

            FontPreview(theme: appModel.theme,
                        font: GlowTheme.makeFont(name: appModel.settings.fontName,
                                                 size: appModel.settings.fontSize))
        }
        .padding(20)
    }
}

/// A theme rendered as a tiny terminal: chrome strip, prompt line, and its
/// eight normal ANSI colors as a swatch row.
private struct ThemeCard: View {
    let theme: GlowTheme
    let selected: Bool
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color(nsColor: theme.separator))
                            .frame(width: 5, height: 5)
                    }
                    Spacer()
                    Text(theme.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(nsColor: theme.foreground).opacity(0.6))
                }
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Color(nsColor: theme.chrome))

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        Text("~ ")
                            .foregroundColor(Color(nsColor: theme.ansiNS(4)))
                        Text("% ")
                            .foregroundColor(Color(nsColor: theme.foreground))
                        Text("ls")
                            .foregroundColor(Color(nsColor: theme.foreground))
                        Rectangle()
                            .fill(Color(nsColor: theme.caret))
                            .frame(width: 5, height: 9)
                            .padding(.leading, 2)
                    }
                    .font(.system(size: 9, design: .monospaced))
                    HStack(spacing: 2) {
                        ForEach(1..<7, id: \.self) { index in
                            Rectangle()
                                .fill(Color(nsColor: theme.ansiNS(index)))
                                .frame(height: 4)
                        }
                    }
                }
                .padding(7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: theme.background))
            }
            .overlay(
                Rectangle()
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(hovering ? 0.35 : 0.15),
                            lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(theme.displayName)
    }
}

/// A few lines of sample output in the chosen theme and font.
private struct FontPreview: View {
    let theme: GlowTheme
    let font: NSFont

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line([("~/project/glow ", 4), ("main ", 5), ("% ", -1), ("git status", -1)])
            line([("On branch main", -1)])
            line([("  modified:   ", 1), ("Sources/Glow/GlowApp.swift", 1)])
            line([("  new file:   ", 2), ("Sources/Glow/Support/GitBranch.swift", 2)])
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: theme.background))
        .overlay(Rectangle().stroke(Color(nsColor: theme.separator), lineWidth: 1))
    }

    /// Segments of (text, ANSI index); -1 is the plain foreground.
    private func line(_ segments: [(String, Int)]) -> some View {
        segments.reduce(Text("")) { result, segment in
            let color = segment.1 < 0 ? theme.foreground : theme.ansiNS(segment.1)
            return result + Text(segment.0).foregroundColor(Color(nsColor: color))
        }
        .font(Font(font))
        .lineLimit(1)
    }
}

private struct GeneralSettings: View {
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        Form {
            Section {
                Toggle("Open last layout on launch", isOn: $appModel.settings.openLastLayoutOnLaunch)
                Toggle("Notify when a command finishes in the background", isOn: $appModel.settings.notifyOnCommandDone)
                Toggle("Global hotkey (Ctrl+`) to show/hide Glow", isOn: $appModel.settings.globalHotkeyEnabled)
            }
            Section {
                Toggle("Confirm before closing a tab with a running process", isOn: $appModel.settings.confirmBeforeClosingRunningProcess)
            }
        }
        .formStyle(.grouped)
        .frame(height: 220)
    }
}
