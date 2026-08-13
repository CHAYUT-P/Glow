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
                    .frame(width: 210)
                Divider()
            }
            VStack(spacing: 0) {
                TabBarView(model: model)
                ZStack {
                    ForEach(model.tabs) { tab in
                        TabPaneView(tab: tab, model: model)
                            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
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
            } else if let axis = pane.axis, let children = pane.children, children.count == 2 {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Divider()
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                } else {
                    VStack(spacing: 0) {
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
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .stroke(Color.accentColor.opacity(isFocused ? 0.6 : 0), lineWidth: 1.5)
    }
}
