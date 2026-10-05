import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Drag type carried by tab and pane drags (tab reorder, drag-tab-to-split,
/// drag-pane-to-tab). Unique to Glow, so drop targets can accept these drags
/// and nothing else: Finder files never carry this type, so they can never
/// trigger split UI.
let GlowTabDragType = UTType(exportedAs: "com.glow.tab-drag")

/// What an in-app drag is carrying: a whole tab grabbed in the tab bar, or a
/// single pane pulled out of a split tab by its grip.
enum GlowDragItem {
    case tab(UUID)
    case pane(tabID: UUID, sessionID: UUID)

    /// The tab the dragged content comes from (the tab itself, or the split
    /// tab owning the dragged pane).
    var sourceTabID: UUID {
        switch self {
        case .tab(let id): return id
        case .pane(let tabID, _): return tabID
        }
    }

    /// Pasteboard payload ("uuid" for tabs, "tabUUID:sessionUUID" for panes).
    var payload: String {
        switch self {
        case .tab(let id): return id.uuidString
        case .pane(let tabID, let sessionID): return "\(tabID.uuidString):\(sessionID.uuidString)"
        }
    }

    init?(payload: String) {
        let parts = payload.split(separator: ":").map(String.init)
        if parts.count == 2,
           let tabID = UUID(uuidString: parts[0]),
           let sessionID = UUID(uuidString: parts[1]) {
            self = .pane(tabID: tabID, sessionID: sessionID)
            return
        }
        guard let id = UUID(uuidString: payload.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self = .tab(id)
    }
}

/// In-process registry for the item currently being dragged. SwiftUI's drag
/// sessions don't materialize data into the pasteboard for in-app drags
/// (the pasteboard only carries the type), so the dragged item is passed
/// through this shared state, set when the drag starts. The pasteboard type
/// is still what *identifies* the drag as a Glow drag.
enum TabDragState {
    static var current: GlowDragItem?
}

/// Minimal tab strip: a sidebar toggle, flat tab chips (color dot, title,
/// attention dot, close ×), and a new-tab button. Every v1 interaction is
/// kept: click to select, inline rename, full context menu, drag to reorder
/// and drag onto terminals to split.
struct TabBarView: View {
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    /// Accent line after the last tab while a pane drag hovers empty tab-bar
    /// space — marks where the popped-out pane's tab will land.
    @State private var endInsertion = false

    var body: some View {
        HStack(spacing: 2) {
            // Left-most: sidebar toggle — 28×28 hit target
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { model.sidebarVisible.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.55))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .background(Rectangle().fill(Color.primary.opacity(0.001)))
            }
            .buttonStyle(.plain)
            .help("Toggle Folder Sidebar (⌘⌥S)")

            ForEach(model.tabs) { tab in
                GlowTabItemView(model: model, tab: tab)
            }

            if endInsertion {
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.accent))
                    .frame(width: 2, height: 22)
            }

            // New tab — same 28×28 target for symmetry
            Button {
                model.newTab()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
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
        .onDrop(of: [GlowTabDragType, UTType.fileURL],
                delegate: TabBarDropDelegate(model: model, endInsertion: $endInsertion))
    }
}

/// Drop target covering the whole tab bar — the parts not claimed by a tab
/// item (the 2px gaps, the + button, the trailing spacer). Pane drags
/// landing here pop out into a new last tab, marked by the end-insertion
/// line; Finder folders still open a new tab. Tab drags are deliberately
/// not repositioned here — the item delegates own placement (including "to
/// the end" via the last tab's right half), so hovering a gap doesn't yank
/// the dragged tab to the back of the bar.
private struct TabBarDropDelegate: DropDelegate {
    let model: WindowModel
    @Binding var endInsertion: Bool

    /// The dragged Glow item — trusted only when the drag actually carries
    /// Glow's type. `TabDragState.current` can stay set after a cancelled
    /// drag, which would otherwise hijack a later Finder file drop.
    private func glowItem(_ info: DropInfo) -> GlowDragItem? {
        info.hasItemsConforming(to: [GlowTabDragType.identifier]) ? TabDragState.current : nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        if let item = glowItem(info) {
            // Only accept drags this window can act on (a tab dragged onto
            // another window's bar is rejected, not swallowed).
            return model.tabs.contains { $0.id == item.sourceTabID }
        }
        return info.hasItemsConforming(to: [UTType.fileURL.identifier])
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        if glowItem(info) != nil { return DropProposal(operation: .move) }
        return info.hasItemsConforming(to: [UTType.fileURL.identifier]) ? DropProposal(operation: .copy) : nil
    }

    private func update(_ info: DropInfo) {
        switch glowItem(info) {
        case .pane: endInsertion = true
        default: endInsertion = false
        }
    }

    func dropExited(info: DropInfo) {
        endInsertion = false
    }

    func performDrop(info: DropInfo) -> Bool {
        let item = glowItem(info)
        defer {
            endInsertion = false
            TabDragState.current = nil
        }
        switch item {
        case .tab:
            return true // live-reordered during hover; nothing left to do
        case .pane(let sourceTabID, let sessionID):
            model.moveSessionToNewTab(sessionID: sessionID, fromTab: sourceTabID,
                                      atIndex: model.tabs.count)
            return true
        case nil:
            let providers = info.itemProviders(for: [.fileURL])
            guard !providers.isEmpty else { return false }
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

    @ObservedObject private var appModel = AppModel.shared
    @State private var editing = false
    @State private var editingTitle = ""
    @State private var hovering = false
    /// Accent edge shown while a pane drag hovers this tab — where the
    /// popped-out pane's new tab will be inserted.
    @State private var insertionEdge: Edge?
    /// Item width, tracked so the drop delegate can tell left half from right.
    @State private var itemWidth: CGFloat = 0

    private var isSelected: Bool { tab.id == model.selectedTabID }

    var body: some View {
        HStack(spacing: 6) {
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
            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
            .italic(isExited)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: 140)
            .foregroundStyle(textColor)

            if tab.paneCount > 1 {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .help("\(tab.paneCount) panes")
            }

            if tab.attention {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
            }
            Button {
                model.closeTab(id: tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(closeButtonColor)
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Tab")
            // Only the hovered or selected tab shows its ×, so a full bar
            // reads as titles rather than a row of close buttons. The slot
            // keeps its width so titles don't shift on hover.
            .opacity(hovering || isSelected ? 1 : 0)
            .allowsHitTesting(hovering || isSelected)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(tabBackground)
        )
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.accent))
                    .frame(height: 2)
            }
        }
        .overlay(alignment: .leading) {
            if insertionEdge == .leading { insertionLine }
        }
        .overlay(alignment: .trailing) {
            if insertionEdge == .trailing { insertionLine }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { itemWidth = geo.size.width }
                    .onChange(of: geo.size.width) { itemWidth = $0 }
            }
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.1), value: hovering)
        .onTapGesture { model.selectTab(id: tab.id) }
        .contextMenu { tabContextMenu }
        .onDrag {
            TabDragState.current = .tab(tab.id)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: GlowTabDragType.identifier, visibility: .ownProcess) { completion in
                completion(GlowDragItem.tab(tab.id).payload.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [GlowTabDragType],
                delegate: TabItemDropDelegate(model: model, target: tab,
                                              targetWidth: itemWidth,
                                              insertionEdge: $insertionEdge))
    }

    private var insertionLine: some View {
        Rectangle()
            .fill(Color(nsColor: appModel.theme.accent))
            .frame(width: 2)
    }

    /// Every shell in the tab has exited — the title dims and italicizes.
    private var isExited: Bool {
        !tab.allSessions.contains { $0.isRunning }
    }

    private var textColor: Color {
        if isExited { return Color.secondary.opacity(0.7) }
        if isSelected { return .primary }
        return .secondary
    }

    private var closeButtonColor: Color {
        hovering ? Color.secondary : Color.primary.opacity(0.3)
    }

    private var tabBackground: Color {
        if isSelected { return Color.primary.opacity(0.08) }
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
            Button("Move Pane to New Tab") {
                model.selectTab(id: tab.id)
                model.moveFocusedPaneToNewTab()
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

/// Drop target on one tab item. Two behaviors:
/// - Dragging a **tab** reorders live: the dragged tab slides to the gap under
///   the cursor (left half of this tab → before it, right half → after), like
///   browser tab bars. The drop itself only ends the drag.
/// - Dragging a **pane** shows an accent insertion line on the edge where the
///   popped-out pane's new tab will land; dropping moves the pane's session
///   into a new tab there.
private struct TabItemDropDelegate: DropDelegate {
    let model: WindowModel
    let target: Tab
    let targetWidth: CGFloat
    @Binding var insertionEdge: Edge?

    /// Same gate as TabBarDropDelegate: only trust shared drag state when
    /// the drag actually carries Glow's type.
    private func glowItem(_ info: DropInfo) -> GlowDragItem? {
        info.hasItemsConforming(to: [GlowTabDragType.identifier]) ? TabDragState.current : nil
    }

    /// Gap index in `model.tabs` where a drop would insert — `i` means
    /// "before tab i", `tabs.count` means "after the last tab".
    private func gapIndex(_ info: DropInfo) -> Int {
        let index = model.tabs.firstIndex { $0.id == target.id } ?? model.tabs.count
        return info.location.x <= targetWidth / 2 ? index : index + 1
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard let item = glowItem(info) else { return false }
        return model.tabs.contains { $0.id == item.sourceTabID }
    }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }

    private func update(_ info: DropInfo) {
        switch glowItem(info) {
        case .tab(let draggedID):
            insertionEdge = nil
            guard draggedID != target.id else { return }
            let gap = gapIndex(info)
            withAnimation(.easeInOut(duration: 0.15)) {
                model.moveTab(draggedID: draggedID, toGap: gap)
            }
        case .pane:
            insertionEdge = info.location.x <= targetWidth / 2 ? .leading : .trailing
        case nil:
            insertionEdge = nil
        }
    }

    func dropExited(info: DropInfo) {
        insertionEdge = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let item = glowItem(info)
        defer {
            insertionEdge = nil
            if item != nil { TabDragState.current = nil }
        }
        switch item {
        case .tab:
            return true // live-reordered during hover; nothing left to do
        case .pane(let sourceTabID, let sessionID):
            model.moveSessionToNewTab(sessionID: sessionID, fromTab: sourceTabID,
                                      atIndex: gapIndex(info))
            return true
        case nil:
            return false
        }
    }
}
