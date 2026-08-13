import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @ObservedObject var model: WindowModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { session in
                TabItemView(session: session, model: model)
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
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            FolderDrop.handle(providers) { url in
                model.openFolderInNewTab(url.path)
            }
            return true
        }
    }
}

private struct TabItemView: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var model: WindowModel
    @State private var editing = false
    @State private var editingTitle = ""

    private var isSelected: Bool { session.id == model.selectedTabID }

    var body: some View {
        HStack(spacing: 5) {
            if let color = Color(hex: session.colorHex) {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            if editing {
                TextField("", text: $editingTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 110)
                    .onSubmit { commitRename() }
            } else {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 130)
            }
            if session.attention {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Button {
                model.closeTab(id: session.id)
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
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { model.selectTab(id: session.id) }
        .contextMenu { tabContextMenu }
        .onDrag { NSItemProvider(object: session.id.uuidString as NSString) }
        .onDrop(of: [UTType.text], delegate: TabDropDelegate(sourceID: session.id, model: model))
    }

    private var tabContextMenu: some View {
        VStack {
            Button("Rename…") { beginRename() }
            Button("Reset Title") { session.resetTitle() }
            Menu("Tab Color") {
                Button("None") { session.colorHex = "" }
                ForEach(GlowTheme.tabColors, id: \.hex) { item in
                    Button(item.name) { session.colorHex = item.hex }
                }
            }
            Divider()
            Button("Set Start Command…") { model.promptSetStartCommand(for: session) }
            Button("Run Start Command") { model.runStartCommand(for: session) }
            Divider()
            Button("Restart Session") { session.restart() }
                .disabled(session.isRunning)
            Divider()
            Button("Copy Last Output") { session.copyLastBlock() }
            Divider()
            Button("Close Tab") { model.closeTab(id: session.id) }
        }
    }

    private func beginRename() {
        editingTitle = session.title
        editing = true
    }

    private func commitRename() {
        editing = false
        session.setCustomTitle(editingTitle)
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
