import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's local-process terminal view.
///
/// Two hooks are needed by Glow:
/// - `send(source:data:)` is the single funnel for user input going to the PTY.
///   A carriage return (0x0D) means a command line was submitted, which anchors
///   "copy last block".
/// - `rangeChanged` fires on every visual change when `notifyUpdateChanges` is
///   on; it drives output-activity tracking for the "command finished" notice.
///   SwiftTerm calls it from its feed (background) queue, so it hops to main.
final class GlowTerminalView: LocalProcessTerminalView {
    var onCommandSubmit: (() -> Void)?
    var onActivity: (() -> Void)?
    var onFocus: (() -> Void)?

    override init(frame: CGRect, font: NSFont? = nil, options: TerminalOptions) {
        super.init(frame: frame, font: font, options: options)
        commonInit()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        notifyUpdateChanges = true
        scrollerStyle = .overlay
        optionAsMetaKey = true
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if data.contains(13) {
            onCommandSubmit?()
        }
        super.send(source: source, data: data)
    }

    override func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        DispatchQueue.main.async { [weak self] in
            self?.onActivity?()
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onFocus?()
    }
}
