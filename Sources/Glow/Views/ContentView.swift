import AppKit
import SwiftUI

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
                    .frame(width: 224)
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.separator))
                    .frame(width: 1)
            }
            VStack(spacing: 0) {
                TabBarView(model: model)
                ZStack {
                    ForEach(model.tabs) { tab in
                        TabStackItem(tab: tab, model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: appModel.theme.background))
                TerminalToolbarView(model: model)
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

/// One tab in the ZStack. Identity stays the same when selection changes;
/// switching selected vs `.hidden()` rebuilt the representable and SwiftUI's
/// default dismantle removed the shared terminal NSView from its new parent.
private struct TabStackItem: View {
    @ObservedObject var tab: Tab
    @ObservedObject var model: WindowModel

    var body: some View {
        let selected = tab.id == model.selectedTabID
        TabPaneView(tab: tab, model: model)
            .padding(4)
            .allowsHitTesting(selected)
            .zIndex(selected ? 1 : 0)
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
    @ObservedObject private var appModel = AppModel.shared
    let pane: Pane

    @State private var dropZone: DropZone?

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
                // Drag-and-drop is handled at the AppKit level by the
                // terminal view itself (see GlowTerminalView) — SwiftUI's
                // DropInfo item-provider bridge loses data for in-app drags,
                // so the view reads the drag pasteboard directly. These
                // callbacks just wire its results into SwiftUI state.
                .onAppear {
                    wireTerminalDropCallbacks(session)
                }
            } else if let axis = pane.axis, let children = pane.children, children.count == 2 {
                if axis == .horizontal {
                    HStack(spacing: 6) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Rectangle()
                            .fill(Color(nsColor: appModel.theme.separator))
                            .frame(width: 1)
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                } else {
                    VStack(spacing: 6) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Rectangle()
                            .fill(Color(nsColor: appModel.theme.separator))
                            .frame(height: 1)
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                }
            }
        }
    }

    /// Wires the terminal view's AppKit drag callbacks into this pane's
    /// SwiftUI state. Updates hop to the next main turn so a drag callback
    /// never mutates `@State` in the middle of a SwiftUI render.
    private func wireTerminalDropCallbacks(_ session: TerminalSession) {
        let tabID = tab.id
        session.terminalView.onDropZone = { zone in
            DispatchQueue.main.async {
                dropZone = zone
            }
        }
        session.terminalView.onTabDropped = { sourceTabID, direction in
            DispatchQueue.main.async {
                if sourceTabID == tabID {
                    model.splitPane(inTab: tabID,
                                    paneSessionID: session.id,
                                    direction: direction)
                } else {
                    guard let sourceTab = model.tabs.first(where: { $0.id == sourceTabID }),
                          let sourceSession = sourceTab.focusedSession else { return }
                    model.moveSession(sessionID: sourceSession.id,
                                      fromTab: sourceTabID,
                                      ontoTab: tabID,
                                      paneSessionID: session.id,
                                      direction: direction)
                }
            }
        }
        session.terminalView.onFilesDropped = { urls in
            DispatchQueue.main.async {
                let text = FilePaste.text(for: urls)
                guard !text.isEmpty else { return }
                session.terminalView.send(txt: text)
                session.terminalView.window?.makeFirstResponder(session.terminalView)
            }
        }
    }

    private func focusBorder(for session: TerminalSession) -> some View {
        let isFocused = isSelectedTab && session.id == tab.focusedSessionID
        return Rectangle()
            .stroke(Color(nsColor: appModel.theme.foreground).opacity(isFocused ? 0.45 : 0), lineWidth: 1)
    }

    @ViewBuilder
    private var dropZoneOverlay: some View {
        if let zone = dropZone {
            GeometryReader { geo in
                let rect = zone.rect(in: geo.size)
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.accent).opacity(0.25))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .allowsHitTesting(false)
        }
    }

}

/// Which half of a pane a drop is over, deciding how the split lands.
enum DropZone {
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
