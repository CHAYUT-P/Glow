import SwiftUI
import UniformTypeIdentifiers

/// Minimal folder sidebar: Home plus recent folders, an Open button, and a
/// status line that previews paths on hover. Click a row to open that folder
/// in a new tab; drop Finder folders anywhere on the sidebar to open them.
struct FolderSidebarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    /// Path previewed in the status bar while hovering a row.
    @State private var previewPath: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sectionHeader("Folders")

                SidebarRow(icon: "house", label: "Home", path: homePath,
                           isActive: activePath == homePath,
                           isOpen: openPaths.contains(homePath),
                           accentColor: accent,
                           onHover: { hovering in preview(hovering, path: homePath) },
                           open: { openFolder(homePath) })
                    .contextMenu {
                        Button("Open in New Tab") { openFolder(homePath) }
                    }

                if !recents.isEmpty {
                    sectionHeader("Recent")
                        .padding(.top, 8)
                }

                ForEach(recents, id: \.self) { folder in
                    SidebarRow(icon: "folder",
                               label: URL(fileURLWithPath: folder).lastPathComponent,
                               path: folder,
                               isActive: activePath == folder,
                               isOpen: openPaths.contains(folder),
                               accentColor: accent,
                               onHover: { hovering in preview(hovering, path: folder) },
                               open: { openFolder(folder) })
                        .contextMenu {
                            Button("Open in New Tab") { openFolder(folder) }
                            Button("Remove from Recents") { appModel.removeRecent(folder) }
                        }
                }

                if recents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 12, weight: .light))
                        Text("Drop a folder from Finder here, or press ⌘O.")
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)

            HStack(spacing: 8) {
                Button {
                    model.openFolderPanel()
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Open a folder in a new tab (⌘O)")

                Spacer(minLength: 8)

                Text(displayPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: appModel.theme.chrome))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            FolderDrop.handle(providers) { url in
                model.openFolderInNewTab(url.path)
            }
            return true
        }
    }

    /// Recent folders minus Home, which always has its own row.
    private var recents: [String] {
        appModel.recentFolders.filter { $0 != homePath }
    }

    /// Folders some tab in this window is currently sitting in.
    private var openPaths: Set<String> {
        Set(model.tabs.flatMap { $0.allSessions.map(\.cwd) })
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private var activePath: String? {
        model.selectedSession?.cwd ?? model.selectedFolder
    }

    private var accent: Color { Color(nsColor: appModel.theme.accent) }

    private var displayPath: String {
        if let previewPath { return shortPath(previewPath) }
        if let activePath { return shortPath(activePath) }
        return ""
    }

    private var homePath: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func preview(_ hovering: Bool, path: String) {
        if hovering {
            previewPath = path
        } else if previewPath == path {
            previewPath = nil
        }
    }

    private func openFolder(_ folder: String) {
        model.openFolderInNewTab(folder)
    }
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

/// One folder row: small icon, name, whole row is the click target. Hover
/// highlights and previews the path in the status bar; the folder matching
/// the focused pane's cwd gets an accent edge, and folders open in any tab
/// get a small dot on the right.
private struct SidebarRow: View {
    let icon: String
    let label: String
    let path: String
    let isActive: Bool
    let isOpen: Bool
    let accentColor: Color
    let onHover: (Bool) -> Void
    let open: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(label)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if isOpen {
                Circle()
                    .fill(Color.primary.opacity(isActive ? 0.5 : 0.25))
                    .frame(width: 4, height: 4)
                    .help("Open in a tab")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .foregroundStyle(isActive || hovering ? Color.primary : Color.secondary)
        .background(
            Rectangle()
                .fill(isActive ? Color.primary.opacity(0.09)
                               : (hovering ? Color.primary.opacity(0.05) : .clear))
        )
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
            onHover(hovering)
        }
        .onTapGesture { open() }
        .help(path)
    }
}
