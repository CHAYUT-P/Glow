import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared
    @Environment(\.openWindow) private var openWindow
    @FocusState private var findFocused: Bool

    /// The app delegate's manual-NSWindow fallback hosts this view outside
    /// any WindowGroup — its `openWindow` has no scene behind it, so letting
    /// it register would poison `WindowOpener` with a no-op and break every
    /// later dock-reopen/hotkey call.
    private let registersWindowOpener: Bool

    init(request: GlowWindowRequest, registersWindowOpener: Bool = true) {
        _model = StateObject(wrappedValue: WindowModel(request: request))
        self.registersWindowOpener = registersWindowOpener
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
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.findVisible)
        }
        .frame(minWidth: 720, minHeight: 440)
        .preferredColorScheme(appModel.theme.colorScheme)
        .tint(Color(nsColor: appModel.theme.accent))
        .focusedSceneValue(\.windowModel, model)
        .environmentObject(model)
        .onAppear {
            // Hand the scene's openWindow to the app delegate so dock-reopen
            // and the global hotkey create real WindowGroup windows (menu
            // commands rely on the scene's focused values).
            if registersWindowOpener {
                WindowOpener.open = { openWindow(value: $0) }
            }
        }
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
                .overlay(dropZoneOverlay)
                // Breathing room between the text grid and the window edge,
                // painted in the terminal's own background so it reads as
                // part of the terminal.
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: appModel.theme.background))
                .overlay(unfocusedDim(for: session).allowsHitTesting(false))
                .overlay(alignment: .topTrailing) {
                    // Split tabs get a grip to pull a pane back out: drag it
                    // onto the tab bar for a new tab, or onto another pane
                    // to rearrange the split.
                    if tab.paneCount > 1 {
                        PaneGrip(session: session, tabID: tab.id)
                    }
                }
                .overlay(ResizeHUD(session: session).allowsHitTesting(false))
                .overlay(SessionExitedOverlay(session: session, tab: tab, model: model))
                // Drag-and-drop is handled at the AppKit level by the
                // terminal view itself (see GlowTerminalView) — SwiftUI's
                // DropInfo item-provider bridge loses data for in-app drags,
                // so the view reads the drag pasteboard directly. These
                // callbacks just wire its results into SwiftUI state.
                .onAppear {
                    wireTerminalDropCallbacks(session)
                }
                // A leaf slot belongs to its session, not its position: when a
                // pane move leaves the tree shape unchanged (e.g. swapping two
                // panes), this forces the whole leaf to rebuild — fresh
                // representable showing the right terminal view, and onAppear
                // re-firing so the new session's drop callbacks wire into this
                // slot's state instead of keeping the old session's bindings.
                .id(session.id)
            } else if let axis = pane.axis, let children = pane.children, children.count == 2 {
                if axis == .horizontal {
                    HStack(spacing: 0) {
                        PaneNodeView(tab: tab, model: model, pane: children[0])
                        Rectangle()
                            .fill(Color(nsColor: appModel.theme.separator))
                            .frame(width: 1)
                        PaneNodeView(tab: tab, model: model, pane: children[1])
                    }
                } else {
                    VStack(spacing: 0) {
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
    /// never mutates `@State` in the middle of a SwiftUI render. `session`
    /// and `model` are captured weakly — the view storing these closures is
    /// owned by the session, which is owned by the model, so strong captures
    /// would cycle (WindowModel → Tab → Pane → session → view → closures →
    /// WindowModel) and leak the whole window graph on close. `self` can't
    /// be captured either — its `@ObservedObject` wrapper retains `model` —
    /// so the zone update goes through the `@State` Binding, which only
    /// references SwiftUI's state storage.
    private func wireTerminalDropCallbacks(_ session: TerminalSession) {
        let tabID = tab.id
        let dropZoneBinding = $dropZone
        session.terminalView.onDropZone = { zone in
            DispatchQueue.main.async {
                dropZoneBinding.wrappedValue = zone
            }
        }
        session.terminalView.canAcceptDragItem = { [weak model] item in
            model?.tabs.contains { $0.id == item.sourceTabID } ?? false
        }
        session.terminalView.onDragItemDropped = { [weak session, weak model] item, direction in
            DispatchQueue.main.async {
                guard let session, let model else { return }
                switch item {
                case .tab(let sourceTabID):
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
                case .pane(let sourceTabID, let sessionID):
                    if sourceTabID == tabID {
                        model.movePane(sessionID: sessionID,
                                       inTab: tabID,
                                       ontoPaneSessionID: session.id,
                                       direction: direction)
                    } else {
                        model.moveSession(sessionID: sessionID,
                                          fromTab: sourceTabID,
                                          ontoTab: tabID,
                                          paneSessionID: session.id,
                                          direction: direction)
                    }
                }
            }
        }
        session.terminalView.onFilesDropped = { [weak session] urls in
            DispatchQueue.main.async {
                guard let session else { return }
                let text = FilePaste.text(for: urls)
                guard !text.isEmpty else { return }
                session.terminalView.send(txt: text)
                session.terminalView.window?.makeFirstResponder(session.terminalView)
            }
        }
    }

    /// In a split, the panes without focus sink back under a veil of the
    /// page color, so the active one stands out without boxing it in. A
    /// single-pane tab never dims.
    private func unfocusedDim(for session: TerminalSession) -> some View {
        let dimmed = tab.paneCount > 1 && session.id != tab.focusedSessionID
        return Rectangle()
            .fill(Color(nsColor: appModel.theme.background).opacity(dimmed ? 0.38 : 0))
            .animation(.easeOut(duration: 0.12), value: dimmed)
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

/// Drag handle floating at a split pane's top-right corner — six-dot grip in
/// a hairline chip, matching the tab bar's flat chrome. Dragging it carries
/// a `.pane` item: drop on the tab bar to pop the pane out into a real tab,
/// or on another pane to re-dock it on that side of the split.
private struct PaneGrip: View {
    @ObservedObject var session: TerminalSession
    let tabID: UUID

    @ObservedObject private var appModel = AppModel.shared
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    Circle().frame(width: 2, height: 2)
                    Circle().frame(width: 2, height: 2)
                }
            }
        }
        .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(hovering ? 0.8 : 0.3))
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(
            Rectangle()
                .fill(Color(nsColor: appModel.theme.chrome).opacity(hovering ? 0.95 : 0.75))
        )
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: appModel.theme.separator), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag {
            TabDragState.current = .pane(tabID: tabID, sessionID: session.id)
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: GlowTabDragType.identifier, visibility: .ownProcess) { completion in
                completion(GlowDragItem.pane(tabID: tabID, sessionID: session.id).payload.data(using: .utf8), nil)
                return nil
            }
            return provider
        }
        .help("Drag pane — drop on the tab bar for a new tab, or on another pane to move it")
        // Extra trailing inset keeps the chip off the terminal's overlay
        // scrollbar lane at the pane's right edge.
        .padding(.top, 4)
        .padding(.trailing, 14)
    }
}

/// Brief `cols × rows` pill centered on a pane while it is being resized,
/// like iTerm — fades out shortly after the size settles. Size changes in
/// the first moments after the pane appears (initial layout) are ignored.
private struct ResizeHUD: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject private var appModel = AppModel.shared

    @State private var visible = false
    @State private var appearedAt = Date()
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        Text("\(session.gridSize.cols) × \(session.gridSize.rows)")
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(nsColor: appModel.theme.foreground))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Rectangle().fill(Color(nsColor: appModel.theme.chrome)))
            .overlay(Rectangle().stroke(Color(nsColor: appModel.theme.separator), lineWidth: 1))
            .opacity(visible ? 1 : 0)
            .onAppear { appearedAt = Date() }
            .onChange(of: session.gridSize) { _ in
                guard Date().timeIntervalSince(appearedAt) > 0.8,
                      session.terminalView.window != nil,
                      !session.terminalView.isHidden else { return }
                withAnimation(.easeOut(duration: 0.08)) { visible = true }
                hideWork?.cancel()
                let work = DispatchWorkItem {
                    withAnimation(.easeIn(duration: 0.25)) { visible = false }
                }
                hideWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
            }
    }
}

/// Shown over a pane whose shell has exited: the exit status plus Restart
/// (fresh shell in the last cwd) and Close. Return in the dead terminal also
/// restarts (handled by GlowTerminalView, so it never steals Return from a
/// live pane elsewhere).
private struct SessionExitedOverlay: View {
    @ObservedObject var session: TerminalSession
    @ObservedObject var tab: Tab
    @ObservedObject var model: WindowModel
    @ObservedObject private var appModel = AppModel.shared

    var body: some View {
        if !session.isRunning {
            ZStack {
                Rectangle()
                    .fill(Color(nsColor: appModel.theme.background).opacity(0.55))
                VStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.5))
                    Text(statusText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.85))
                    Text(shortPath(session.cwd))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(nsColor: appModel.theme.foreground).opacity(0.45))
                    HStack(spacing: 8) {
                        overlayButton("Restart  ↩", prominent: true) { restart() }
                        overlayButton(tab.paneCount > 1 ? "Close Pane" : "Close Tab", prominent: false) {
                            close()
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(Rectangle().fill(Color(nsColor: appModel.theme.chrome)))
                .overlay(Rectangle().stroke(Color(nsColor: appModel.theme.separator), lineWidth: 1))
            }
            .transition(.opacity)
        }
    }

    private var statusText: String {
        // SwiftTerm reports the raw waitpid status: exit code in bits 8–15,
        // terminating signal in the low 7 bits.
        guard let status = session.exitCode else { return "Process exited" }
        let signal = status & 0x7F
        if signal != 0 { return "Process terminated by signal \(signal)" }
        let code = (status >> 8) & 0xFF
        return code == 0 ? "Process exited" : "Process exited with code \(code)"
    }

    private func restart() {
        session.restart()
        model.focusPane(sessionID: session.id)
    }

    private func close() {
        model.focusPane(sessionID: session.id)
        model.closeFocusedPaneOrTab()
    }

    private func overlayButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(prominent
                    ? Color(nsColor: appModel.theme.background)
                    : Color(nsColor: appModel.theme.foreground).opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Rectangle().fill(prominent
                    ? Color(nsColor: appModel.theme.foreground).opacity(0.9)
                    : Color.clear))
                .overlay(Rectangle().stroke(Color(nsColor: appModel.theme.separator), lineWidth: prominent ? 0 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
