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
            Button("Close Tab") { windowModel?.closeSelectedTab() }
                .keyboardShortcut("w", modifiers: .command)
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

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.persistNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func closeTabInKeyWindow() -> Bool {
        guard let keyWindow = NSApp.keyWindow,
              !(keyWindow is NSPanel),
              let model = WindowRegistry.model(for: keyWindow) else { return false }
        model.closeSelectedTab()
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
            // No window exists (user closed it); just bring the app forward.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
