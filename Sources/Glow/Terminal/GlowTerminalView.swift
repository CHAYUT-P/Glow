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
    var onActivity: (() -> Void)?
    var onFocus: (() -> Void)?

    /// Called while a tab drag hovers the view: the half the cursor is over
    /// (or nil when the drag leaves/ends), so SwiftUI can draw the split
    /// preview.
    var onDropZone: ((DropZone?) -> Void)?
    /// Called when a tab is dropped: the dragged tab's ID and which side of
    /// this pane the split should land on.
    var onTabDropped: ((UUID, PaneDirection) -> Void)?
    /// Called when files are dropped: their URLs, to be inserted as paths.
    var onFilesDropped: (([URL]) -> Void)?

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
        // Glow draws its own accent focus border around the active pane, so
        // suppress the system's blue focus ring (drawn outside the view).
        focusRingType = .none
        registerForDraggedTypes([
            .init(GlowTabDragType.identifier),
            .fileURL,
        ])
    }

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
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
        let isTabDrag = types.contains(.init(GlowTabDragType.identifier)) || TabDragState.currentTabID != nil
        if types.contains(.fileURL) && !isTabDrag {
            TabDragState.currentTabID = nil
            currentDragIsFile = true
            onDropZone?(nil)
            return .copy
        }
        if isTabDrag {
            currentDragIsFile = false
            updateZone(for: sender)
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if currentDragIsFile { return .copy }
        updateZone(for: sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        lastDropZone = nil
        onDropZone?(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        onDropZone?(nil)
        defer {
            lastDropZone = nil
            currentDragIsFile = false
        }

        // Tabs: SwiftUI in-app drags put only the type on the pasteboard,
        // not the data — so the dragged tab's ID comes from shared state
        // (set when the drag started in the tab bar). Pasteboard decoding
        // is kept as a fallback for any future drag source.
        if let id = TabDragState.currentTabID {
            TabDragState.currentTabID = nil
            deliverTabDrop(id)
            return true
        }
        if let data = pasteboard.data(forType: .init(GlowTabDragType.identifier)),
           let string = String(data: data, encoding: .utf8),
           let id = UUID(uuidString: string.trimmingCharacters(in: .whitespacesAndNewlines)) {
            deliverTabDrop(id)
            return true
        }

        // Files: read the URLs synchronously from the pasteboard.
        if pasteboard.types?.contains(.fileURL) == true {
            TabDragState.currentTabID = nil
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
        TabDragState.currentTabID = nil
    }

    private func updateZone(for sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let rx = point.x / bounds.width
        let ry = point.y / bounds.height
        var zone: DropZone
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

    private func deliverTabDrop(_ sourceTabID: UUID) {
        let direction: PaneDirection
        switch lastDropZone {
        case .left: direction = .left
        case .right: direction = .right
        case .top: direction = .up
        case .bottom: direction = .down
        case nil: direction = .right
        }
        onTabDropped?(sourceTabID, direction)
    }
}
