import AppKit
import SwiftTerm
import SwiftUI

/// Bridges one TerminalSession's SwiftTerm view into SwiftUI. All sessions stay
/// mounted (so their PTYs keep running); sessions in non-selected tabs are
/// hidden so they are not drawn, which keeps idle CPU near zero.
///
/// Work happens only when visibility or focus actually changes, so unrelated
/// model updates stay cheap and pane/tab switching is immediate.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    let isVisible: Bool
    let isFocused: Bool
    let suppressFocus: Bool

    @EnvironmentObject var windowModel: WindowModel

    final class Coordinator {
        var wasVisible = false
        var wasFocused = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalView {
        session.terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        windowModel.attachWindow(nsView.window)
        let coordinator = context.coordinator
        let visibleChanged = isVisible != coordinator.wasVisible
        let focusedChanged = isFocused != coordinator.wasFocused
        coordinator.wasVisible = isVisible
        coordinator.wasFocused = isFocused

        guard visibleChanged || focusedChanged else { return }

        nsView.isHidden = !isVisible
        if isVisible, visibleChanged {
            // Force a clean full redraw now that the view is visible again.
            session.terminalView.terminal.updateFullScreen()
            nsView.needsDisplay = true
        }
        if isFocused, focusedChanged, !suppressFocus {
            focus(nsView)
        }
    }

    private func focus(_ nsView: TerminalView) {
        guard let window = nsView.window else {
            // Window not attached yet (initial layout); retry once it is.
            DispatchQueue.main.async { [weak nsView] in
                guard let view = nsView, let win = view.window, win.firstResponder !== view else { return }
                win.makeFirstResponder(view)
            }
            return
        }
        if window.firstResponder !== nsView {
            window.makeFirstResponder(nsView)
        }
    }
}
