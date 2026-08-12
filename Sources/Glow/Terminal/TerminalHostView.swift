import AppKit
import SwiftTerm
import SwiftUI

/// Bridges one TerminalSession's SwiftTerm view into SwiftUI. All sessions stay
/// mounted (so their PTYs keep running); inactive ones are hidden so they are
/// not drawn, which keeps idle CPU near zero.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    let isActive: Bool
    let suppressFocus: Bool

    @EnvironmentObject var windowModel: WindowModel

    func makeNSView(context: Context) -> TerminalView {
        session.terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        windowModel.attachWindow(nsView.window)
        nsView.isHidden = !isActive
        guard isActive, !suppressFocus else { return }
        if nsView.window != nil, nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { [weak nsView] in
                guard let view = nsView, let win = view.window, win.firstResponder !== view else { return }
                win.makeFirstResponder(view)
            }
        }
    }
}
