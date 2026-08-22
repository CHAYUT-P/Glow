import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Terminal-styled sidebar. Not a real terminal — a plain SwiftUI view
/// decorated with monospace type, box-drawing rules and prompt-like
/// affordances (row indexes, `~` home glyph, `:open ⏎` command, blinking
/// block cursor).
///
/// UX: single click opens (like the Finder sidebar), the whole row is the
/// hit target, hovering reveals the `▸` marker and previews the path in the
/// status bar. The folder matching the focused pane's cwd is marked active.
struct FolderSidebarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    /// Path previewed in the status bar while hovering a row.
    @State private var previewPath: String?
    @State private var hoveringOpen = false
    @State private var cursorOn = true


    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader
                tabsSection
                placesSection
                foldersSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.bottom, 8)
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
            statusBar
        }
        .background(Color(nsColor: appModel.theme.chrome))
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            FolderDrop.handle(providers) { url in
                model.openFolderInNewTab(url.path)
            }
            return true
        }
    }

    // MARK: - Header

    private var brandHeader: some View {
        HStack(spacing: 0) {
            Text("┌─ ")
                .foregroundStyle(faint)
            Text("glow")
                .foregroundStyle(accent)
            Text(" ")
                .foregroundStyle(faint)
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var activePath: String? {
        model.selectedSession?.cwd ?? model.selectedFolder
    }

    private var tabsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("tabs", count: model.tabs.count)
            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                let sessionPath = tab.focusedSession?.cwd ?? tab.focusedSession?.folder
                SidebarTabRow(model: model, tab: tab, index: index,
                              isActive: tab.id == model.selectedTabID,
                              accentColor: accent,
                              onPreview: { previewPath = sessionPath },
                              onPreviewEnd: { if previewPath == sessionPath { previewPath = nil } })
            }
        }
        .padding(.top, 10)
    }

    private var placesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("places", count: nil)
            SidebarPlaceRow(glyph: "~", label: "home",
                            isActive: activePath == homePath,
                            accentColor: accent,
                            path: homePath,
                            onPreview: { previewPath = homePath },
                            onPreviewEnd: { if previewPath == homePath { previewPath = nil } },
                            open: { openFolder(homePath) })
                .contextMenu {
                    Button("Open in New Tab") { openFolder(homePath) }
                }
        }
        .padding(.top, 12)
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("folders",
                          count: appModel.recentFolders.isEmpty ? nil : appModel.recentFolders.count)
            if appModel.recentFolders.isEmpty {
                emptyHint("drop a folder here")
            } else {
                ForEach(Array(appModel.recentFolders.enumerated()), id: \.element) { index, folder in
                    SidebarPlaceRow(index: index,
                                    label: URL(fileURLWithPath: folder).lastPathComponent,
                                    isActive: activePath == folder,
                                    accentColor: accent,
                                    path: folder,
                                    onPreview: { previewPath = folder },
                                    onPreviewEnd: { if previewPath == folder { previewPath = nil } },
                                    open: { openFolder(folder) })
                        .contextMenu {
                            Button("Open in New Tab") { openFolder(folder) }
                            Button("Remove from Recents") { appModel.removeRecent(folder) }
                        }
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: - Status bar

    private var statusBar: some View {
        HStack(spacing: 8) {
            Button {
                model.openFolderPanel()
            } label: {
                Text(":open ⏎")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Rectangle().fill(hoveringOpen ? accent.opacity(0.3) : Color.clear))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(accent.opacity(hoveringOpen ? 0.9 : 0))
                            .frame(height: 1)
                            .padding(.horizontal, 6)
                    }
            }
            .buttonStyle(.plain)
            .onHover { hoveringOpen = $0 }
            .help("Open a folder in a new tab (⌘O)")

            Spacer(minLength: 8)

            Text(previewPath ?? model.selectedFolder.map(shortPath) ?? "—")
                .foregroundStyle(previewPath != nil ? fg : secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)

            // Blinking block cursor — the terminal's pulse.
            Rectangle()
                .fill(accent)
                .frame(width: 6, height: 11)
                .opacity(cursorOn ? 0.9 : 0.05)
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Building blocks

    private func sectionHeader(_ label: String, count: Int?) -> some View {
        HStack(spacing: 0) {
            Text("-- \(label)")
                .foregroundStyle(secondary)
            if let count {
                Text(" [\(count)]")
                    .foregroundStyle(faint)
            }
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.leading, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 3)
    }

    private func emptyHint(_ text: String) -> some View {
        Text("  ∅ \(text)")
            .foregroundStyle(faint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
    }

    private func openFolder(_ folder: String) {
        model.openFolderInNewTab(folder)
    }

    private var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    // MARK: - Colors

    private var fg: Color { Color(nsColor: appModel.theme.foreground) }
    private var secondary: Color { fg.opacity(0.55) }
    private var faint: Color { fg.opacity(0.30) }
    private var accent: Color { Color(nsColor: appModel.theme.accent) }
}

// MARK: - zsh-style path abbreviation

/// `/Users/chayut/project/glow` → `~/p/glow` — every component except the
/// last collapses to its initial, like zsh's tilde-path tricks.
func shortPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var p = path
    if p.hasPrefix(home) {
        p = "~" + p.dropFirst(home.count)
    }
    let parts = p.split(separator: "/").map(String.init)
    guard parts.count > 1 else { return p.isEmpty ? "/" : p }
    let head = parts.dropLast().map { $0 == "~" ? "~" : String($0.prefix(1)) }
    return (head + [parts.last!]).joined(separator: "/")
}

// MARK: - Rows

/// One row in the `places` / `folders` sections. Single click opens the
/// folder in a new tab; hovering shows the `▸` marker and highlights the row.
private struct SidebarPlaceRow: View {
    var index: Int?
    var glyph: String?
    let label: String
    let isActive: Bool
    let accentColor: Color
    let path: String
    let onPreview: () -> Void
    let onPreviewEnd: () -> Void
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(isActive || hovering ? "▸" : " ")
                .foregroundStyle(accentColor)
                .frame(width: 11)
            if let glyph {
                Text(glyph)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 18, alignment: .leading)
            } else {
                Text(String(format: "%02d ", (index ?? 0) + 1))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .frame(width: 18, alignment: .leading)
            }
            Text(label)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
        }
        .foregroundStyle(textColor)
        .padding(.vertical, 5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            self.hovering = hovering
            if hovering { onPreview() } else { onPreviewEnd() }
        }
        .onTapGesture { open() }
        .help(path)
    }

    private var textColor: Color {
        isActive || hovering ? Color.primary : Color.secondary
    }

    private var rowBackground: Color {
        isActive ? accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.06) : .clear)
    }
}

/// One row in the `tabs` section: index, color dot, tab title. Single click
/// selects the tab; hovering previews its cwd in the status bar; context
/// menu offers Select/Close.
private struct SidebarTabRow: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: Tab
    let index: Int
    let isActive: Bool
    let accentColor: Color
    let onPreview: () -> Void
    let onPreviewEnd: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(isActive || hovering ? "▸" : " ")
                .foregroundStyle(accentColor)
                .frame(width: 11)
            Text(String(format: "%02d", index + 1))
                .foregroundStyle(Color.secondary.opacity(0.55))
                .frame(width: 18, alignment: .leading)
            dot
            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if tab.attention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
        }
        .font(.system(size: 11, weight: isActive ? .medium : .regular, design: .monospaced))
        .foregroundStyle(textColor)
        .padding(.vertical, 5)
        .background(background)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(accentColor)
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            self.hovering = hovering
            if hovering { onPreview() } else { onPreviewEnd() }
        }
        .onTapGesture { model.selectTab(id: tab.id) }
        .contextMenu {
            Button("Select Tab") { model.selectTab(id: tab.id) }
            Divider()
            Button("Close Tab") { model.closeTab(id: tab.id) }
        }
        .help(tab.focusedSession?.cwd ?? tab.title)
    }

    @ViewBuilder
    private var dot: some View {
        if !tab.colorHex.isEmpty, let color = Color(hex: tab.colorHex) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .padding(.trailing, 5)
        } else {
            Color.clear
                .frame(width: 7, height: 7)
                .padding(.trailing, 5)
        }
    }

    private var textColor: Color {
        isActive || hovering ? Color.primary : Color.secondary
    }

    private var background: Color {
        isActive ? accentColor.opacity(0.16) : (hovering ? Color.primary.opacity(0.06) : .clear)
    }
}
