import AppKit
import Combine
import SwiftTerm

/// One shell session: owns a PTY-backed terminal view, its title/color, its
/// start command, and the small amount of per-tab state Glow needs
/// (cwd, activity tracking for notifications, block-copy anchor).
final class TerminalSession: ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminalView: GlowTerminalView
    var folder: String
    var startCommand: String?

    @Published var title: String
    @Published var colorHex: String
    @Published var attention = false
    @Published private(set) var isRunning = true

    private(set) var cwd: String

    private var titleIsCustom = false
    private var lastActivity = Date()
    private var burstStart: Date?
    private var blockAnchorText: String?

    init(folder: String, title: String?, colorHex: String?, startCommand: String?) {
        self.folder = folder
        self.cwd = folder
        let folderName = URL(fileURLWithPath: folder).lastPathComponent
        self.title = (title?.isEmpty == false) ? title! : (folderName.isEmpty ? "terminal" : folderName)
        self.colorHex = colorHex ?? ""
        self.startCommand = startCommand
        let options = TerminalOptions(scrollback: 10_000)
        let view = GlowTerminalView(frame: .zero, options: options)
        self.terminalView = view
        view.onCommandSubmit = { [weak self] in self?.noteCommandSubmit() }
        view.onActivity = { [weak self] in self?.noteActivity() }
        view.processDelegate = self
        applyAppearance()
        start()
    }

    private func start() {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = "en_US.UTF-8"
        // The child process is chdir'd by the PTY spawn, but zsh/bash also honor
        // a $PWD environment variable; pin it so shells start in `folder`.
        env["PWD"] = folder
        let envArray = env.map { "\($0.key)=\($0.value)" }.sorted()
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        terminalView.startProcess(executable: shell, args: ["-l"], environment: envArray, currentDirectory: folder)
        if let cmd = startCommand, !cmd.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.waitForShellThenSend(cmd)
            }
        }
    }

    /// Wait for the shell to print a prompt (or a short timeout), then run the
    /// start command as if typed, keeping the shell alive underneath.
    private func waitForShellThenSend(_ cmd: String) {
        var attempts = 0
        var poll: (() -> Void)?
        poll = { [weak self] in
            attempts += 1
            guard let self = self else { return }
            let data = self.terminalView.terminal.getBufferAsData(kind: .active)
            if !data.isEmpty || attempts > 30 {
                self.terminalView.send(txt: cmd + "\r")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll?() }
            }
        }
        poll?()
    }

    func close() {
        terminalView.terminate()
    }

    /// Restarts the shell in the same folder (and re-runs the start command).
    /// Only meaningful after the previous process terminated.
    func restart() {
        guard !isRunning else { return }
        start()
    }

    // MARK: - Block copy

    private func noteCommandSubmit() {
        let data = terminalView.terminal.getBufferAsData(kind: .active)
        blockAnchorText = String(data: data, encoding: .utf8)
    }

    /// Copies the text between the last submitted command and the end of the
    /// scrollback. Anchored on the buffer text captured at Enter; falls back
    /// to a prompt-line heuristic when no anchor exists.
    func copyLastBlock() {
        let data = terminalView.terminal.getBufferAsData(kind: .active)
        let text = String(data: data, encoding: .utf8) ?? ""
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard !lines.isEmpty else { return }

        var start = 0
        if let anchor = blockAnchorText {
            let anchorLines = anchor.components(separatedBy: "\n")
            var common = 0
            while common < min(anchorLines.count, lines.count), anchorLines[common] == lines[common] {
                common += 1
            }
            // common points at the first line that changed after the anchor;
            // step back one so the submitted command line itself is included.
            start = max(0, common - 1)
        } else {
            for i in stride(from: lines.count - 1, through: 0, by: -1) {
                let line = lines[i]
                if !line.isEmpty, line.count < 300,
                   line.range(of: "[$%#>]\\s*$", options: .regularExpression) != nil {
                    start = i + 1
                    break
                }
            }
        }

        if start >= lines.count { start = max(0, lines.count - 1) }
        var block = Array(lines[start...])
        while block.last?.isEmpty == true { block.removeLast() }
        let result = block.joined(separator: "\n")
        guard !result.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(result, forType: .string)
    }

    // MARK: - Activity / attention

    private func noteActivity() {
        lastActivity = Date()
        if burstStart == nil { burstStart = lastActivity }
    }

    /// Forget any burst recorded while Glow was in the foreground. The
    /// attention timer only runs in the background, so output that was visible
    /// on screen must not be treated as a background burst on the next app
    /// switch.
    func resetAttentionTracking() {
        burstStart = nil
        lastActivity = Date()
    }

    /// Called on a timer by the window: if a burst of output ended more than
    /// ~2.5s ago and the burst ran longer than 5s, and Glow is not in front,
    /// mark the tab and bounce the Dock icon once.
    func tickAttention(appInactive: Bool, windowUnfocused: Bool) {
        guard let burst = burstStart else { return }
        let now = Date()
        if now.timeIntervalSince(lastActivity) > 2.5 {
            if now.timeIntervalSince(burst) > 5.0, (appInactive || windowUnfocused), !attention {
                attention = true
                _ = NSApp.requestUserAttention(.informationalRequest)
            }
            burstStart = nil
        }
    }

    // MARK: - Edits

    func setCustomTitle(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            title = trimmed
            titleIsCustom = true
        }
    }

    func resetTitle() {
        titleIsCustom = false
        let folderName = URL(fileURLWithPath: folder).lastPathComponent
        title = folderName.isEmpty ? "terminal" : folderName
    }

    func applyAppearance() {
        let theme = AppModel.shared.theme
        let settings = AppModel.shared.settings
        let view = terminalView
        view.wantsLayer = true
        view.nativeBackgroundColor = theme.background
        view.nativeForegroundColor = theme.foreground
        view.caretColor = theme.caret
        view.selectedTextBackgroundColor = theme.selectionBackground
        view.selectedTextForegroundColor = theme.selectionForeground
        view.layer?.backgroundColor = theme.background.cgColor
        view.font = GlowTheme.makeFont(name: settings.fontName, size: settings.fontSize)
        view.installColors(theme.ansi)
        view.needsDisplay = true
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        // SwiftTerm may call this from its feed queue.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.titleIsCustom, !title.isEmpty, self.title != title else { return }
            self.title = title
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.cwd = directory
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
        }
    }
}
