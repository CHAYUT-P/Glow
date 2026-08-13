import AppKit
import Combine
import SwiftTerm
import SwiftUI

/// What a new window should contain. Used as the WindowGroup scene value so
/// "Open Layout" can spawn a window that already has the layout's tabs running.
enum GlowWindowRequest: Hashable, Codable {
    case plain
    case layout(SavedLayout)
}

/// Per-window state: the tabs (each a tree of split panes), selection,
/// sidebar/find UI state, and the attention timer that watches background
/// output.
final class WindowModel: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var selectedTabID: UUID?
    @Published var sidebarVisible = true
    @Published var selectedFolder: String?

    @Published var findVisible = false
    @Published var findText = ""
    @Published var findCaseSensitive = false
    @Published var findMatchIndex = 0
    @Published var findMatchTotal = 0
    @Published var findFocusRequest = 0

    @Published var isKeyWindow = false

    weak var window: NSWindow?

    private var attentionTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var appSettingsObserver: NSObjectProtocol?

    var selectedTab: Tab? {
        guard let id = selectedTabID else { return nil }
        return tabs.first { $0.id == id }
    }

    var selectedSession: TerminalSession? {
        selectedTab?.focusedSession
    }

    private var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    init(request: GlowWindowRequest) {
        switch request {
        case .plain:
            if AppModel.shared.consumeRestoreOnLaunch(), let last = AppModel.shared.layouts.last {
                restore(layout: last)
            } else {
                newTab(folder: homeDirectory, title: nil, colorHex: nil, startCommand: nil)
            }
        case .layout(let layout):
            restore(layout: layout)
        }
        startAttentionTimer()
        observeNotifications()
    }

    deinit {
        attentionTimer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if let appSettingsObserver { NotificationCenter.default.removeObserver(appSettingsObserver) }
        for tab in tabs {
            for session in tab.allSessions {
                session.close()
            }
        }
    }

    // MARK: - Sessions

    private func makeSession(folder: String, title: String?, colorHex: String?, startCommand: String?) -> TerminalSession {
        let session = TerminalSession(folder: folder, title: title, colorHex: colorHex, startCommand: startCommand)
        session.terminalView.onFocus = { [weak self, weak session] in
            guard let self, let id = session?.id else { return }
            self.focusPane(sessionID: id)
        }
        return session
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(folder: String? = nil, title: String? = nil, colorHex: String? = nil,
                startCommand: String? = nil, select: Bool = true) -> Tab {
        let dir = folder ?? selectedFolder ?? selectedSession?.cwd ?? homeDirectory
        let session = makeSession(folder: dir, title: title, colorHex: colorHex, startCommand: startCommand)
        let tab = Tab(session: session)
        tabs.append(tab)
        if select {
            selectTab(id: tab.id)
        }
        return tab
    }

    func selectTab(id: UUID) {
        selectedTabID = id
        if let tab = tabs.first(where: { $0.id == id }) {
            for session in tab.allSessions {
                session.attention = false
            }
            if let focused = tab.focusedSession {
                selectedFolder = focused.cwd
            }
        }
    }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(id: tabs[index].id)
    }

    func selectPreviousTab() {
        guard !tabs.isEmpty else { return }
        let index = selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? 0
        selectTab(id: tabs[(index - 1 + tabs.count) % tabs.count].id)
    }

    func selectNextTab() {
        guard !tabs.isEmpty else { return }
        let index = selectedTabID.flatMap { id in tabs.firstIndex { $0.id == id } } ?? 0
        selectTab(id: tabs[(index + 1) % tabs.count].id)
    }

    func clearScrollback() {
        selectedSession?.terminalView.terminal.clearScrollback()
    }

    private struct ClosedTabSnapshot {
        let folder: String
        let title: String
        let colorHex: String
        let startCommand: String?
    }

    private var closedTabs: [ClosedTabSnapshot] = []

    func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        let focused = tab.focusedSession
        closedTabs.append(ClosedTabSnapshot(
            folder: focused?.folder ?? homeDirectory,
            title: focused?.title ?? "",
            colorHex: focused?.colorHex ?? "",
            startCommand: focused?.startCommand
        ))
        if closedTabs.count > 10 { closedTabs.removeFirst(closedTabs.count - 10) }
        tabs.remove(at: index)
        for session in tab.allSessions {
            session.close()
        }
        if selectedTabID == id {
            selectedTabID = tabs.last?.id
        }
        if tabs.isEmpty {
            newTab(folder: homeDirectory, title: nil, colorHex: nil, startCommand: nil)
        }
    }

    func reopenClosedTab() {
        guard let snapshot = closedTabs.popLast() else { return }
        newTab(folder: snapshot.folder, title: snapshot.title,
               colorHex: snapshot.colorHex, startCommand: snapshot.startCommand)
    }

    func closeSelectedTab() {
        if let id = selectedTabID { closeTab(id: id) }
    }

    /// ⌘W: close the focused pane when the tab has several panes; otherwise
    /// close the whole tab.
    func closeFocusedPaneOrTab() {
        guard let tab = selectedTab else { return }
        if tab.paneCount > 1 {
            tab.closeFocusedPane()
        } else {
            closeSelectedTab()
        }
    }

    func moveTab(from sourceID: UUID, to targetID: UUID) {
        guard let from = tabs.firstIndex(where: { $0.id == sourceID }),
              let to = tabs.firstIndex(where: { $0.id == targetID }), from != to else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
    }

    // MARK: - Panes

    func splitSelectedPane(axis: PaneAxis) {
        guard let tab = selectedTab, let focused = tab.focusedSession else { return }
        let newSession = makeSession(folder: focused.cwd, title: nil, colorHex: focused.colorHex, startCommand: nil)
        tab.split(paneSessionID: focused.id, axis: axis, newSession: newSession, placingFirst: false)
    }

    /// Splits the pane under a drop with a fresh session (dragging a tab onto
    /// its own terminal). Direction decides which side the new pane lands on.
    func splitPane(inTab tabID: UUID, paneSessionID: UUID, direction: PaneDirection) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let paneSession = tab.session(withID: paneSessionID) else { return }
        let (axis, placingFirst) = splitPlacement(for: direction)
        let newSession = makeSession(folder: paneSession.cwd, title: nil,
                                     colorHex: paneSession.colorHex, startCommand: nil)
        tab.split(paneSessionID: paneSessionID, axis: axis, newSession: newSession, placingFirst: placingFirst)
        selectTab(id: tab.id)
    }

    /// Moves a session from one tab into a split of another tab's pane
    /// (dragging a tab onto a terminal in a different tab).
    func moveSession(sessionID: UUID, fromTab sourceTabID: UUID, ontoTab targetTabID: UUID,
                     paneSessionID: UUID, direction: PaneDirection) {
        guard sourceTabID != targetTabID,
              let sourceTab = tabs.first(where: { $0.id == sourceTabID }),
              let targetTab = tabs.first(where: { $0.id == targetTabID }),
              let session = sourceTab.session(withID: sessionID),
              targetTab.session(withID: paneSessionID) != nil else { return }

        let (axis, placingFirst) = splitPlacement(for: direction)
        targetTab.split(paneSessionID: paneSessionID, axis: axis, newSession: session, placingFirst: placingFirst)

        if !sourceTab.detach(sessionID: session.id) {
            removeEmptyTab(sourceTabID)
        }
        selectTab(id: targetTabID)
    }

    private func splitPlacement(for direction: PaneDirection) -> (PaneAxis, Bool) {
        switch direction {
        case .left: return (.horizontal, true)
        case .right: return (.horizontal, false)
        case .up: return (.vertical, true)
        case .down: return (.vertical, false)
        }
    }

    private func removeEmptyTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab(folder: homeDirectory, title: nil, colorHex: nil, startCommand: nil)
        }
    }

    func focusPane(sessionID: UUID) {
        guard let tab = selectedTab else { return }
        tab.focus(sessionID: sessionID)
        guard let session = tab.focusedSession, let win = session.terminalView.window else { return }
        if win.firstResponder !== session.terminalView {
            win.makeFirstResponder(session.terminalView)
        }
    }

    func focusPane(direction: PaneDirection) {
        selectedTab?.focus(direction: direction)
    }

    // MARK: - Folders

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Open Folder"
        panel.message = "Choose a folder to open in a new tab"
        if panel.runModal() == .OK, let url = panel.url {
            AppModel.shared.addRecent(url.path)
            newTab(folder: url.path)
        }
    }

    func openFolderInNewTab(_ path: String) {
        AppModel.shared.addRecent(path)
        newTab(folder: path)
    }

    // MARK: - Layouts

    func promptSaveLayout() {
        let alert = NSAlert()
        alert.messageText = "Save Layout"
        alert.informativeText = "Name this layout. It saves every open tab, its folder, color and start command."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "e.g. Work"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { saveLayout(name: name) }
        }
    }

    func saveLayout(name: String) {
        let saved = tabs.compactMap { tab in
            tab.focusedSession.map { session in
                SavedTab(title: session.title, colorHex: session.colorHex,
                         folder: session.cwd, startCommand: session.startCommand)
            }
        }
        AppModel.shared.addLayout(SavedLayout(name: name, tabs: saved))
    }

    func restore(layout: SavedLayout) {
        for tab in layout.tabs {
            newTab(folder: tab.folder, title: tab.title, colorHex: tab.colorHex,
                   startCommand: tab.startCommand, select: false)
        }
        if tabs.isEmpty {
            newTab(folder: homeDirectory, title: nil, colorHex: nil, startCommand: nil)
        } else {
            selectTab(id: tabs[0].id)
        }
    }

    // MARK: - Start commands

    func promptSetStartCommand(for session: TerminalSession) {
        let alert = NSAlert()
        alert.messageText = "Start Command"
        alert.informativeText = "The tab opens this folder and runs this command once the shell is ready."

        let folderField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        folderField.stringValue = session.folder
        folderField.placeholderString = "Folder"
        let commandField = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        commandField.stringValue = session.startCommand ?? ""
        commandField.placeholderString = "Command (e.g. grok)"
        let stack = NSStackView(views: [folderField, commandField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setHuggingPriority(.defaultLow, for: .horizontal)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = commandField
        if alert.runModal() == .alertFirstButtonReturn {
            let folder = folderField.stringValue.trimmingCharacters(in: .whitespaces)
            let command = commandField.stringValue.trimmingCharacters(in: .whitespaces)
            if !folder.isEmpty { session.folder = folder }
            session.startCommand = command.isEmpty ? nil : command
        }
    }

    func runStartCommand(for session: TerminalSession) {
        if let cmd = session.startCommand, !cmd.isEmpty {
            session.terminalView.send(txt: cmd + "\r")
        }
    }

    // MARK: - Find

    private var searchOptions: SearchOptions {
        SearchOptions(caseSensitive: findCaseSensitive, regex: false, wholeWord: false)
    }

    func showFind() {
        if findVisible {
            findFocusRequest += 1
        } else {
            findVisible = true
            findFocusRequest += 1
        }
        updateFindSummary()
    }

    func closeFind() {
        findVisible = false
        selectedSession?.terminalView.clearSearch()
        findText = ""
        findMatchIndex = 0
        findMatchTotal = 0
        focusTerminal()
    }

    func onFindTextChanged() {
        guard let view = selectedSession?.terminalView else { return }
        if findText.isEmpty {
            view.clearSearch()
            findMatchIndex = 0
            findMatchTotal = 0
            return
        }
        _ = view.findNext(findText, options: searchOptions)
        updateFindSummary()
    }

    func findNext() {
        guard let view = selectedSession?.terminalView, !findText.isEmpty else { return }
        _ = view.findNext(findText, options: searchOptions)
        updateFindSummary()
    }

    func findPrevious() {
        guard let view = selectedSession?.terminalView, !findText.isEmpty else { return }
        _ = view.findPrevious(findText, options: searchOptions)
        updateFindSummary()
    }

    func updateFindSummary() {
        guard let view = selectedSession?.terminalView, !findText.isEmpty else {
            findMatchIndex = 0
            findMatchTotal = 0
            return
        }
        let (index, total) = view.searchMatchSummary(findText, options: searchOptions)
        findMatchIndex = index
        findMatchTotal = total
    }

    // MARK: - Actions

    func copyLastOutput() {
        selectedSession?.copyLastBlock()
    }

    func focusTerminal() {
        guard let view = selectedSession?.terminalView, let win = view.window else { return }
        win.makeFirstResponder(view)
    }

    // MARK: - Appearance

    func applyAppearanceToAll() {
        for tab in tabs {
            for session in tab.allSessions {
                session.applyAppearance()
            }
        }
    }

    // MARK: - Window state

    func attachWindow(_ newWindow: NSWindow?) {
        guard window !== newWindow else { return }
        window = newWindow
        if let newWindow {
            isKeyWindow = newWindow.isKeyWindow
            WindowRegistry.register(window: newWindow, model: self)
        }
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let w = note.object as? NSWindow, w === self?.window else { return }
            self?.isKeyWindow = true
            // Return focus to the terminal when the user comes back to Glow,
            // unless they're in the middle of a find.
            if self?.findVisible != true {
                self?.focusTerminal()
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            guard let w = note.object as? NSWindow, w === self?.window else { return }
            self?.isKeyWindow = false
        })
        appSettingsObserver = nc.addObserver(forName: .glowSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyAppearanceToAll()
        }
    }

    private func startAttentionTimer() {
        attentionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.checkAttention()
        }
    }

    private func checkAttention() {
        guard AppModel.shared.settings.notifyOnCommandDone else { return }
        let appInactive = !NSApp.isActive
        for tab in tabs {
            for session in tab.allSessions {
                session.tickAttention(appInactive: appInactive, windowUnfocused: !isKeyWindow)
            }
        }
    }
}

/// Weak window → WindowModel map so AppKit-side code (e.g. the Cmd+W
/// interception in the app delegate) can reach the focused window's model.
enum WindowRegistry {
    static let table = NSMapTable<NSWindow, WindowModel>(keyOptions: .weakMemory, valueOptions: .weakMemory)

    static func register(window: NSWindow, model: WindowModel) {
        table.setObject(model, forKey: window)
    }

    static func model(for window: NSWindow) -> WindowModel? {
        table.object(forKey: window)
    }
}
