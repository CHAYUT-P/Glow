import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag type carried by tab drags (tab reorder + drag-tab-to-split). Unique
/// to Glow, so drop targets can accept tab drags and nothing else: Finder
/// files never carry this type, so they can never trigger split UI.
let GlowTabDragType = UTType(exportedAs: "com.glow.tab-drag")

/// In-process registry for the tab currently being dragged. SwiftUI's drag
/// sessions don't materialize data into the pasteboard for in-app drags
/// (the pasteboard only carries the type), so the dragged tab's ID is
/// passed through this shared state, set when the drag starts. The
/// pasteboard type is still what *identifies* the drag as a tab drag.
enum TabDragState {
    static var currentTabID: UUID?
}

struct TabBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Toggle Folder Sidebar")
            ForEach(model.tabs) { tab in
                TabItemView(tab: tab, model: model)
            }
            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("New Tab")
            Spacer(minLength: 8)
        }
        .padding(.leading, 76) // leave room for the traffic lights (hidden title bar)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: appModel.theme.chrome))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(nsColor: appModel.theme.separator))
                .frame(height: 1)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            FolderDrop.handle(providers) { url in
                model.openFolderInNewTab(url.path)
            }
            return true
        }
    }
}

private struct TabItemView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: WindowModel
    @State private var editing = false
    @State private var editingTitle = ""
    @State private var hovering = false

    private var isSelected: Bool { tab.id == model.selectedTabID }

    var body: some View {
        HStack(spacing: 5) {
            if let color = Color(hex: tab.colorHex) {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            if editing {
                TextField("", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 110)
                    .onSubmit { commitRename() }
            } else {
                Text(tab.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            if tab.attention {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Button {
                model.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
            .buttonStyle(.plain)
            .help("Close Tab")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(tabBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.selectTab(id: tab.id) }
        .contextMenu { tabContextMenu }
        .onDrag {
            TabDragState.currentTabID = tab.id
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: GlowTabDragType.identifier, visibility: .ownProcess) { completion in
                completion(tab.id.uuidString.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [GlowTabDragType], isTargeted: nil) { _ in
            guard let draggedID = TabDragState.currentTabID else { return false }
            TabDragState.currentTabID = nil
            model.moveTab(from: draggedID, to: tab.id)
            return true
        }
    }

    private var tabBackground: Color {
        if isSelected {
            return Color.primary.opacity(0.12)
        }
        if hovering {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var tabContextMenu: some View {
        VStack {
            Button("Rename…") { beginRename() }
            Button("Reset Title") { tab.focusedSession?.resetTitle() }
            Menu("Tab Color") {
                Button("None") { tab.focusedSession?.colorHex = "" }
                ForEach(GlowTheme.tabColors, id: \.hex) { item in
                    Button(item.name) { tab.focusedSession?.colorHex = item.hex }
                }
            }
            Divider()
            Button("Split Right") {
                model.selectTab(id: tab.id)
                model.splitSelectedPane(axis: .horizontal)
            }
            Button("Split Down") {
                model.selectTab(id: tab.id)
                model.splitSelectedPane(axis: .vertical)
            }
            Button("Close Pane") {
                model.selectTab(id: tab.id)
                model.closeFocusedPaneOrTab()
            }
            .disabled(tab.paneCount <= 1)
            Divider()
            if let session = tab.focusedSession {
                Button("Set Start Command…") { model.promptSetStartCommand(for: session) }
                Button("Run Start Command") { model.runStartCommand(for: session) }
            }
            Divider()
            Button("Restart Session") { tab.focusedSession?.restart() }
                .disabled(tab.focusedSession?.isRunning ?? true)
            Divider()
            Button("Copy Last Output") { tab.focusedSession?.copyLastBlock() }
            Divider()
            Button("Close Tab") { model.closeTab(id: tab.id) }
        }
    }

    private func beginRename() {
        editingTitle = tab.title
        editing = true
    }

    private func commitRename() {
        editing = false
        tab.focusedSession?.setCustomTitle(editingTitle)
    }
}
