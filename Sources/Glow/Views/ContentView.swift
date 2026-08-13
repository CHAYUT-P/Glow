import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    @FocusState private var findFocused: Bool

    init(request: GlowWindowRequest) {
        _model = StateObject(wrappedValue: WindowModel(request: request))
    }

    var body: some View {
        HStack(spacing: 0) {
            if model.sidebarVisible {
                FolderSidebarView(model: model)
                    .frame(width: 210)
                Divider()
            }
            VStack(spacing: 0) {
                TabBarView(model: model)
                ZStack {
                    ForEach(model.tabs) { tab in
                        TabPaneView(tab: tab, model: model)
                            .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: appModel.theme.background))
                if model.findVisible {
                    FindBarView(model: model, findFocused: $findFocused)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .preferredColorScheme(appModel.theme.colorScheme)
        .tint(Color(nsColor: appModel.theme.accent))
        .focusedSceneValue(\.windowModel, model)
        .environmentObject(model)
        .onChange(of: model.findFocusRequest) { _ in
            findFocused = true
        }
    }
}

/// Renders one tab's split-pane tree. Every pane stays mounted; only the
/// selected tab's panes are visible, and only the focused pane draws its
/// focus border and receives keyboard focus.
private struct TabPaneView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: WindowModel

    var body: some View {
        PaneNodeView(tab: tab, model: model, pane: tab.root)
    }
}

private struct PaneNodeView: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: WindowModel
    let pane: Pane

    @State private var dropZone: DropZone?
    @State private var paneSize: CGSize = .zero

    private var isSelectedTab: Bool { tab.id == model.selectedTabID }

    var body: some View {
        Group {
            if let session = pane.session {
                TerminalHostView(
                    session: session,
                    isVisible: isSelectedTab,
                    isFocused: isSelectedTab && session.id == tab.focusedSessionID,
                    suppressFocus: model.findVisible
                )
                .overlay(focusBorder(for: session).allowsHitTesting(false))
                .overlay(dropZoneOverlay)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { paneSize = geo.size }
                            .onChange(of: geo.size) { paneSize = $0 }
                    }
                )
                .onDrop(of: [UTType.text], delegate: PaneDropDelegate(
                    model: model,
                    targetTab: tab,
                    paneSession: session,
                    size: paneSize,
                    onZone: { zone in dropZone = zone }
                ))
            } else if let axis = pane.axis, let children = pane.children, children.count == 2 {
                if axis == .horizontal {
                    HStack(spacing: 6) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Divider()
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                } else {
                    VStack(spacing: 6) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Divider()
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                }
            }
        }
    }

    private func focusBorder(for session: TerminalSession) -> some View {
        let isFocused = isSelectedTab && session.id == tab.focusedSessionID
        return Rectangle()
            .stroke(Color.accentColor.opacity(isFocused ? 0.8 : 0), lineWidth: 1.5)
    }

    @ViewBuilder
    private var dropZoneOverlay: some View {
        if let zone = dropZone, paneSize.width > 0, paneSize.height > 0 {
            let rect = zone.rect(in: paneSize)
            Rectangle()
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }
}

/// Which half of a pane a drop is over, deciding how the split lands.
private enum DropZone {
    case left, right, top, bottom

    func rect(in size: CGSize) -> CGRect {
        switch self {
        case .left: return CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
        case .right: return CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height)
        case .top: return CGRect(x: 0, y: 0, width: size.width, height: size.height / 2)
        case .bottom: return CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
        }
    }
}

/// Handles dropping a tab (dragged from the tab bar) onto a terminal pane.
/// Dragging onto your own tab's terminal splits it with a fresh session;
/// dragging onto another tab's terminal moves that session into a split.
private struct PaneDropDelegate: DropDelegate {
    let model: WindowModel
    let targetTab: Tab
    let paneSession: TerminalSession
    let size: CGSize
    let onZone: (DropZone?) -> Void

    func dropEntered(info: DropInfo) {
        onZone(zone(for: info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        onZone(zone(for: info))
        return DropProposal(operation: .copy)
    }

    func dropExited(info: DropInfo) {
        onZone(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        onZone(nil)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            var idString: String?
            if let data = item as? Data {
                idString = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                idString = string
            }
            guard let idString, let sourceTabID = UUID(uuidString: idString) else { return }
            DispatchQueue.main.async {
                let direction = self.direction(for: info)
                if sourceTabID == self.targetTab.id {
                    self.model.splitPane(inTab: self.targetTab.id,
                                         paneSessionID: self.paneSession.id,
                                         direction: direction)
                } else {
                    guard let sourceTab = self.model.tabs.first(where: { $0.id == sourceTabID }),
                          let session = sourceTab.focusedSession else { return }
                    self.model.moveSession(sessionID: session.id,
                                           fromTab: sourceTabID,
                                           ontoTab: self.targetTab.id,
                                           paneSessionID: self.paneSession.id,
                                           direction: direction)
                }
            }
        }
        return true
    }

    private func zone(for info: DropInfo) -> DropZone? {
        guard size.width > 0, size.height > 0 else { return nil }
        let rx = info.location.x / size.width
        let ry = info.location.y / size.height
        if rx < 0.3 { return .left }
        if rx > 0.7 { return .right }
        if ry < 0.3 { return .top }
        if ry > 0.7 { return .bottom }
        return .right
    }

    private func direction(for info: DropInfo) -> PaneDirection {
        switch zone(for: info) {
        case .left: return .left
        case .right: return .right
        case .top: return .up
        case .bottom: return .down
        case nil: return .right
        }
    }
}
