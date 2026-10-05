import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct GlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Glow", for: GlowWindowRequest.self) { request in
            ContentView(request: request.wrappedValue ?? .plain)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            GlowCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

struct GlowCommands: Commands {
    @ObservedObject private var appModel = AppModel.shared
    @FocusedValue(\.windowModel) private var windowModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(value: GlowWindowRequest.plain) }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Tab") { windowModel?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
            Button("Open Folder…") { windowModel?.openFolderPanel() }
                .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button("Save Layout…") { windowModel?.promptSaveLayout() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }
        CommandMenu("Open Layout") {
            ForEach(appModel.layouts) { layout in
                Button(layout.name) { openWindow(value: GlowWindowRequest.layout(layout)) }
            }
            if appModel.layouts.isEmpty {
                Text("No saved layouts")
            }
        }
        CommandMenu("Panes") {
            Button("Split Right") { windowModel?.splitSelectedPane(axis: .horizontal) }
                .keyboardShortcut("d", modifiers: .command)
            Button("Split Down") { windowModel?.splitSelectedPane(axis: .vertical) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Move Pane to New Tab") { windowModel?.moveFocusedPaneToNewTab() }
                .disabled((windowModel?.selectedTab?.paneCount ?? 0) <= 1)
            Divider()
            Button("Focus Pane Left") { windowModel?.focusPane(direction: .left) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("Focus Pane Right") { windowModel?.focusPane(direction: .right) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button("Focus Pane Up") { windowModel?.focusPane(direction: .up) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Focus Pane Down") { windowModel?.focusPane(direction: .down) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Close Pane") { windowModel?.closeFocusedPaneOrTab() }
                .keyboardShortcut("w", modifiers: .command)
        }
        CommandMenu("View") {
            Button("Toggle Sidebar") { windowModel?.sidebarVisible.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .option])
            Divider()
            Button("Find in Scrollback") { windowModel?.showFind() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Find Next") { windowModel?.findNext() }
                .keyboardShortcut("g", modifiers: .command)
            Button("Find Previous") { windowModel?.findPrevious() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Clear Scrollback") { windowModel?.clearScrollback() }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Increase Font Size") { AppModel.shared.increaseFontSize() }
                .keyboardShortcut("=", modifiers: .command)
            Button("Decrease Font Size") { AppModel.shared.decreaseFontSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Reset Font Size") { AppModel.shared.resetFontSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Copy Last Output") { windowModel?.copyLastOutput() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            Divider()
            Button("Insert File Path…") { windowModel?.insertPickedFiles() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
        }
        CommandMenu("Tabs") {
            Button("Previous Tab") { windowModel?.selectPreviousTab() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Tab") { windowModel?.selectNextTab() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Divider()
            Button("Reopen Closed Tab") { windowModel?.reopenClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Divider()
            ForEach(0..<9, id: \.self) { index in
                Button("Select Tab \(index + 1)") { windowModel?.selectTab(at: index) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled((windowModel?.tabs.count ?? 0) <= index)
            }
        }
    }
}

struct WindowModelKey: FocusedValueKey {
    typealias Value = WindowModel
}

/// The WindowGroup scene's `openWindow`, captured by ContentView on appear.
/// Lets the app delegate (dock reopen, global hotkey) create real
/// WindowGroup windows — a manually built NSWindow is outside any scene, so
/// `.focusedSceneValue` never reaches it and every menu command would no-op.
enum WindowOpener {
    static var open: ((GlowWindowRequest) -> Void)?
}

extension FocusedValues {
    var windowModel: WindowModel? {
        get { self[WindowModelKey.self] }
        set { self[WindowModelKey.self] = newValue }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotkey: GlobalHotkey?
    private var cmdWMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if AppModel.shared.settings.globalHotkeyEnabled {
            let hotkey = GlobalHotkey()
            hotkey.onPressed = { [weak self] in self?.toggleMainWindow() }
            hotkey.register(keyCode: 50, modifiers: UInt32(controlKey)) // Ctrl+` (kVK_ANSI_Grave)
            self.hotkey = hotkey
        }

        // Cmd+W closes the focused tab. A local monitor sees key events before
        // menu key-equivalent resolution, so this reliably beats the default
        // "Close Window" ⌘W and never reaches the shell.
        cmdWMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command), event.keyCode == 13 { // kVK_ANSI_W
                if self?.closeTabInKeyWindow() == true {
                    return nil
                }
            }
            return event
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard AppModel.shared.settings.confirmBeforeClosingRunningProcess else { return .terminateNow }
        // Collect unique WindowModels (a window may appear twice due to transient window lists)
        var seen = Set<ObjectIdentifier>()
        var runningTabs = 0
        var models: [WindowModel] = []
        for win in NSApp.windows {
            guard let m = WindowRegistry.model(for: win) else { continue }
            let id = ObjectIdentifier(m)
            if seen.contains(id) { continue }
            seen.insert(id)
            models.append(m)
            runningTabs += m.tabs.filter { $0.hasRunningJob }.count
        }
        if runningTabs == 0 { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Quit Glow with Running Processes?"
        alert.informativeText = "\(runningTabs) tab(s) have running processes. Quitting will terminate all of them."
        alert.addButton(withTitle: "Terminate & Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            for m in models {
                for tab in m.tabs {
                    for session in tab.allSessions { session.close() }
                }
            }
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.persistNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock click with no visible windows: reopen a fresh window (same as
    /// Cmd+N / the Ctrl+` hotkey when nothing is showing).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func openMainWindow() {
        if let open = WindowOpener.open {
            open(.plain)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // Fallback for before any ContentView has appeared: build the window
        // manually (menu commands won't work in it, but it can't normally
        // happen — SwiftUI always opens a window at launch). It must not
        // register its scene-less openWindow as WindowOpener — that no-op
        // would shadow the real scene opener for all later reopens.
        let content = ContentView(request: .plain, registersWindowOpener: false)
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Glow"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1080, height: 700))
        window.minSize = NSSize(width: 720, height: 440)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeTabInKeyWindow() -> Bool {
        guard let keyWindow = NSApp.keyWindow,
              !(keyWindow is NSPanel),
              let model = WindowRegistry.model(for: keyWindow) else { return false }
        // ⌘W in the find field closes the find bar, not the shell
        // underneath. When find is merely visible and the terminal holds
        // focus, ⌘W falls through and closes the pane as usual.
        if model.findVisible, model.findFieldFocused {
            model.closeFind()
            return true
        }
        // While a text field holds focus (e.g. inline tab rename), swallow
        // ⌘W so it kills neither the tab nor the window mid-edit.
        if keyWindow.firstResponder is NSTextView { return true }
        model.closeFocusedPaneOrTab()
        return true
    }

    private func toggleMainWindow() {
        let windows = NSApp.windows.filter { !($0 is NSPanel) }
        if let visible = windows.first(where: { $0.isVisible }) {
            visible.orderOut(nil)
            NSApp.hide(nil)
        } else if let win = windows.first {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        } else {
            // No window exists (user closed it); open a fresh one.
            openMainWindow()
        }
    }
}
