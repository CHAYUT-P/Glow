import AppKit
import SwiftTerm

/// Subclass of SwiftTerm's local-process terminal view.
///
/// Two hooks are needed by Glow:
/// - `send(source:data:)` is the single funnel for user input going to the PTY.
///   A carriage return (0x0D) means a command line was submitted, which anchors
///   "copy last block".
/// - `dataReceived(slice:)` is the funnel for output coming from the PTY; it
///   drives output-activity tracking for the "command finished" notice. It is
///   dispatched on the process's queue (main, unless a custom one was passed).
///
/// Drag-and-drop is also handled here at the AppKit level: SwiftUI's
/// `DropInfo` item-provider bridge loses data for in-app drags, so the view
/// reads the drag pasteboard directly via `NSDraggingDestination`.
final class GlowTerminalView: LocalProcessTerminalView {
    var onCommandSubmit: (() -> Void)?
    /// Return pressed after the shell exited — the session restarts it.
    var onRestartRequest: (() -> Void)?
    var onActivity: (() -> Void)?
    var onFocus: (() -> Void)?

    /// Lets the window reject Glow drags it can't act on (a tab or pane
    /// dragged in from a different window). Wired by the owning pane view.
    var canAcceptDragItem: ((GlowDragItem) -> Bool)?

    /// Called while a tab/pane drag hovers the view: the half the cursor is
    /// over (or nil when the drag leaves/ends), so SwiftUI can draw the split
    /// preview.
    var onDropZone: ((DropZone?) -> Void)?
    /// Called when a tab or pane is dropped on this view: the dragged item
    /// and which side of this pane the split should land on.
    var onDragItemDropped: ((GlowDragItem, PaneDirection) -> Void)?
    /// Called when files are dropped: their URLs, to be inserted as paths.
    var onFilesDropped: (([URL]) -> Void)?

    /// The session rendered by this view — used to ignore a pane dragged
    /// onto itself (dropping a pane on its own surface is a no-op, so it
    /// gets no drop-zone highlight and no accept cursor).
    var owningSessionID: UUID?

    private var currentDragIsFile = false
    private var lastDropZone: DropZone?

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
        scrollerStyle = .overlay
        optionAsMetaKey = true
        // Glow marks the active pane itself (unfocused split panes dim), so
        // suppress the system's blue focus ring (drawn outside the view).
        focusRingType = .none
        registerForDraggedTypes([
            .init(GlowTabDragType.identifier),
            .fileURL,
        ])
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        if data.contains(13), !process.running, let onRestartRequest {
            onRestartRequest()
            return
        }
        if data.contains(13) {
            onCommandSubmit?()
        }
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        // Only real PTY output counts as activity. Tracking SwiftTerm's
        // rangeChanged instead (visual redraws, cursor blink) keeps an idle
        // terminal "active", so the attention notice fires whenever the app is
        // left, even with nothing running.
        onActivity?()
        super.dataReceived(slice: slice)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onFocus?()
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        // The pasteboard type is the source of truth — TabDragState alone
        // can be stale after a cancelled drag.
        let isGlowDrag = types.contains(.init(GlowTabDragType.identifier))
        if isGlowDrag && (isSelfPaneDrop || !acceptsCurrentDrag()) {
            lastDropZone = nil
            currentDragIsFile = false
            onDropZone?(nil)
            return []
        }
        if types.contains(.fileURL) && !isGlowDrag {
            currentDragIsFile = true
            onDropZone?(nil)
            return .copy
        }
        if isGlowDrag {
            currentDragIsFile = false
            updateZone(for: sender)
            return .move
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if currentDragIsFile { return .copy }
        let types = sender.draggingPasteboard.types ?? []
        guard types.contains(.init(GlowTabDragType.identifier)) else { return [] }
        if isSelfPaneDrop || !acceptsCurrentDrag() {
            lastDropZone = nil
            onDropZone?(nil)
            return []
        }
        updateZone(for: sender)
        return .move
    }

    /// A pane dragged by its grip landing back on its own terminal.
    private var isSelfPaneDrop: Bool {
        guard case .pane(_, let sessionID) = TabDragState.current else { return false }
        return sessionID == owningSessionID
    }

    /// Whether the window can act on the dragged item — rejects cross-window
    /// drags whose source tab this model doesn't own. When no item is in
    /// shared state (foreign drags), defer to the drop itself.
    private func acceptsCurrentDrag() -> Bool {
        guard let item = TabDragState.current else { return true }
        return canAcceptDragItem?(item) ?? true
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        lastDropZone = nil
        currentDragIsFile = false
        onDropZone?(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        onDropZone?(nil)
        defer {
            lastDropZone = nil
            currentDragIsFile = false
        }

        // Tabs/panes: only when the drag actually carries Glow's type.
        // `TabDragState.current` can stay set after a cancelled drag — using
        // it unconditionally would turn a later Finder file drop into a pane
        // split. SwiftUI in-app drags put only the type on the pasteboard,
        // not the data, so the item itself comes from shared state; the
        // pasteboard decode is a fallback for any future drag source.
        if pasteboard.types?.contains(.init(GlowTabDragType.identifier)) == true {
            if let item = TabDragState.current {
                // Rejected drops keep shared state — it belongs to the
                // source window and may still land back there.
                guard accepts(item) else { return false }
                TabDragState.current = nil
                deliverDrop(item)
                return true
            }
            if let data = pasteboard.data(forType: .init(GlowTabDragType.identifier)),
               let string = String(data: data, encoding: .utf8),
               let item = GlowDragItem(payload: string),
               accepts(item) {
                deliverDrop(item)
                return true
            }
            return false
        }

        // Files: read the URLs synchronously from the pasteboard.
        if pasteboard.types?.contains(.fileURL) == true {
            TabDragState.current = nil
            let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return false }
            onFilesDropped?(urls)
            return true
        }
        return false
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        lastDropZone = nil
        currentDragIsFile = false
        onDropZone?(nil)
        TabDragState.current = nil
    }

    /// Final acceptance check at drop time: the window must own the source
    /// tab, and a pane must not land back on its own terminal.
    private func accepts(_ item: GlowDragItem) -> Bool {
        if case .pane(_, let sessionID) = item, sessionID == owningSessionID {
            return false
        }
        return canAcceptDragItem?(item) ?? true
    }

    private func updateZone(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rx = point.x / bounds.width
        // The view isn't flipped: y grows upward, so flip ry so that small
        // values mean the top of the view, matching DropZone's SwiftUI rects.
        let ry = 1 - point.y / bounds.height
        let zone: DropZone
        if rx < 0.3 { zone = .left }
        else if rx > 0.7 { zone = .right }
        else if ry < 0.3 { zone = .top }
        else if ry > 0.7 { zone = .bottom }
        else { zone = .right }
        if zone != lastDropZone {
            lastDropZone = zone
            onDropZone?(zone)
        }
    }

    private func deliverDrop(_ item: GlowDragItem) {
        let direction: PaneDirection
        switch lastDropZone {
        case .left: direction = .left
        case .right: direction = .right
        case .top: direction = .up
        case .bottom: direction = .down
        case nil: direction = .right
        }
        onDragItemDropped?(item, direction)
    }
}
