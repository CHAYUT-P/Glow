import AppKit
import SwiftTerm
import SwiftUI

/// Bridges one TerminalSession's SwiftTerm view into SwiftUI. All sessions stay
/// mounted (so their PTYs keep running); inactive ones are hidden so they are
/// not drawn, which keeps idle CPU near zero.
///
/// Work happens only when the active state actually changes (a tab switch), so
/// unrelated model updates stay cheap and switching is immediate.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    let isActive: Bool
    let suppressFocus: Bool

    @EnvironmentObject var windowModel: WindowModel

    final class Coordinator {
        var wasActive = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TerminalView {
        session.terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        windowModel.attachWindow(nsView.window)
        let coordinator = context.coordinator
        let activeChanged = isActive != coordinator.wasActive
        coordinator.wasActive = isActive

        guard activeChanged else { return }

        nsView.isHidden = !isActive
        if isActive {
            // Force a clean full redraw now that the view is visible again.
            session.terminalView.terminal.updateFullScreen()
            nsView.needsDisplay = true
            if !suppressFocus {
                focus(nsView)
            }
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
