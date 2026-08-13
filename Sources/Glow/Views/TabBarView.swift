import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        HStack(spacing: 4) {
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
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tabBackground)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.selectTab(id: tab.id) }
        .contextMenu { tabContextMenu }
        .onDrag { NSItemProvider(object: tab.id.uuidString as NSString) }
        .onDrop(of: [UTType.text], delegate: TabDropDelegate(sourceID: tab.id, model: model))
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

private struct TabDropDelegate: DropDelegate {
    let sourceID: UUID
    let model: WindowModel

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            var idString: String?
            if let data = item as? Data {
                idString = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                idString = string
            }
            guard let idString, let targetID = UUID(uuidString: idString) else { return }
            DispatchQueue.main.async {
                model.moveTab(from: targetID, to: sourceID)
            }
        }
        return true
    }
}
