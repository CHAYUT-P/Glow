import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FolderSidebarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    @State private var selected: String?
    @State private var hoveringOpen = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selected) {
                Section("Places") {
                    HStack(spacing: 6) {
                        Image(systemName: "house")
                            .foregroundStyle(.secondary)
                        Text("Home")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .tag(homeTag)
                    .onTapGesture(count: 2) { openFolder(NSHomeDirectory()) }
                }
                Section("Recents") {
                    if appModel.recentFolders.isEmpty {
                        Text("Drop a folder here, or use Open…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appModel.recentFolders, id: \.self) { folder in
                            row(for: folder)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .tint(Color(nsColor: appModel.theme.accent))
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    model.openFolderPanel()
                } label: {
                    Label("Open…", systemImage: "folder.badge.plus")
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background(
                            Rectangle()
                                .fill(hoveringOpen ? Color(nsColor: appModel.theme.accent).opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoveringOpen = $0 }
                .help("Open a folder in a new tab")
                Text(model.selectedFolder ?? "No folder selected")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
        }
        .background(Color(nsColor: appModel.theme.chrome))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            FolderDrop.handle(providers) { url in
                model.openFolderInNewTab(url.path)
            }
            return true
        }
    }

    private let homeTag = "__home__"

    private func row(for folder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(URL(fileURLWithPath: folder).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder)
        }
        .tag(folder)
        .onTapGesture(count: 2) { openFolder(folder) }
        .contextMenu {
            Button("Open in New Tab") { openFolder(folder) }
            Button("Remove from Recents") { appModel.removeRecent(folder) }
        }
    }

    private func openFolder(_ folder: String) {
        model.openFolderInNewTab(folder)
    }
}
