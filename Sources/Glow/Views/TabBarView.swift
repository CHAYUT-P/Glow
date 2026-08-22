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

/// Terminal-styled tab strip: monospace `01 name ×` chips with an accent
/// edge on the active tab, tmux-style numbering that follows tab order.
/// Every v1 interaction is kept: click to select, inline rename, color dot,
/// attention dot, close button, full context menu, drag to reorder and
/// drag onto terminals to split.
struct TabBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        HStack(spacing: 2) {
            // Left-most: sidebar toggle — 28×28 hit target
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.sidebarVisible.toggle() }
            } label: {
                Text("≡")
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .background(Rectangle().fill(Color.primary.opacity(0.001)))
            }
            .buttonStyle(.plain)
            .help("Toggle Folder Sidebar (⌘⌥S)")

            ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                GlowTabItemView(model: model, tab: tab, index: index)
            }

            // New tab — same 28×28 target for symmetry
            Button {
                model.newTab()
            } label: {
                Text("+")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .background(Rectangle().fill(Color.primary.opacity(0.001)))
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")

            Spacer(minLength: 8)
        }
        .padding(.leading, model.sidebarVisible ? 8 : 72) // 8 when sidebar is open (right next to the 1px separator), 72 only when hidden to clear traffic lights
        .padding(.trailing, 8)
        .padding(.vertical, 4)
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

private struct GlowTabItemView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject var tab: Tab
    let index: Int

    @ObservedObject private var appModel = AppModel.shared
    @State private var editing = false
    @State private var editingTitle = ""
    @State private var hovering = false

    private var isSelected: Bool { tab.id == model.selectedTabID }

    var body: some View {
        HStack(spacing: 6) {
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.primary.opacity(isSelected ? 0.45 : 0.28))
            if let color = Color(hex: tab.colorHex) {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Group {
                if editing {
                    TextField("", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .onSubmit { commitRename() }
                } else {
                    Text(tab.title)
                }
            }
            .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 120)
            .foregroundStyle(textColor)

            if tab.attention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            Button {
                model.closeTab(id: tab.id)
            } label: {
                Text("×")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(closeButtonColor)
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
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
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.accent))
                    .frame(width: 2)
            }
        }
        .overlay(alignment: .top) {
            // Hairline above the active tab — box-drawn feel.
            Rectangle()
                .fill(Color(nsColor: appModel.theme.accent).opacity(isSelected ? 0.7 : 0))
                .frame(height: 1)
        }
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

    private var textColor: Color {
        if isSelected { return .primary }
        return .secondary
    }

    private var closeButtonColor: Color {
        hovering ? Color.secondary : Color.primary.opacity(0.22)
    }

    private var tabBackground: Color {
        if isSelected { return Color(nsColor: appModel.theme.accent).opacity(0.14) }
        if hovering { return Color.primary.opacity(0.05) }
        return .clear
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
