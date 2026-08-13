import Combine
import Foundation

/// How two panes are arranged inside a tab.
/// `.horizontal` places them side by side; `.vertical` stacks them.
enum PaneAxis {
    case horizontal
    case vertical
}

/// Direction used for keyboard pane navigation.
enum PaneDirection {
    case left
    case right
    case up
    case down
}

/// A node in a tab's split-pane tree. A leaf holds a TerminalSession; a
/// branch holds two children laid out along an axis.
final class Pane {
    let id = UUID()
    var session: TerminalSession?
    var axis: PaneAxis?
    var children: [Pane]?
    weak var parent: Pane?

    var isLeaf: Bool { session != nil }

    init(session: TerminalSession) {
        self.session = session
    }

    init(axis: PaneAxis, children: [Pane]) {
        self.axis = axis
        self.children = children
    }
}

/// One tab: a tree of split panes plus which pane currently has keyboard
/// focus. Re-publishes the focused session's changes so the tab bar stays
/// live (title, color, attention).
final class Tab: ObservableObject, Identifiable {
    let id = UUID()
    private(set) var root: Pane
    @Published private(set) var focusedSessionID: UUID

    private var cancellables: [UUID: AnyCancellable] = [:]

    init(session: TerminalSession) {
        let root = Pane(session: session)
        self.root = root
        self.focusedSessionID = session.id
        subscribe(session)
    }

    var focusedSession: TerminalSession? {
        allSessions.first { $0.id == focusedSessionID }
    }

    var title: String { focusedSession?.title ?? "terminal" }
    var colorHex: String { focusedSession?.colorHex ?? "" }
    var attention: Bool { allSessions.contains { $0.attention } }
    var paneCount: Int { allSessions.count }

    var allSessions: [TerminalSession] {
        var result: [TerminalSession] = []
        collect(from: root, into: &result)
        return result
    }

    private func collect(from pane: Pane, into result: inout [TerminalSession]) {
        if let session = pane.session {
            result.append(session)
        } else if let children = pane.children {
            for child in children {
                collect(from: child, into: &result)
            }
        }
    }

    private func pane(containing id: UUID) -> Pane? {
        findPane(from: root, containing: id)
    }

    private func findPane(from pane: Pane, containing id: UUID) -> Pane? {
        if pane.session?.id == id { return pane }
        if let children = pane.children {
            for child in children {
                if let found = findPane(from: child, containing: id) { return found }
            }
        }
        return nil
    }

    // MARK: - Session observation

    func subscribe(_ session: TerminalSession) {
        cancellables[session.id] = session.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private func unsubscribe(_ session: TerminalSession) {
        cancellables.removeValue(forKey: session.id)
    }

    // MARK: - Pane mutations

    /// Replaces the focused leaf with a split containing the old leaf and a
    /// new pane holding `newSession`, then focuses the new pane.
    func split(focusedSessionID: UUID, axis: PaneAxis, newSession: TerminalSession) {
        guard let leaf = pane(containing: focusedSessionID) else { return }
        subscribe(newSession)

        let newLeaf = Pane(session: newSession)
        let split = Pane(axis: axis, children: [leaf, newLeaf])
        split.parent = leaf.parent
        leaf.parent = split
        newLeaf.parent = split

        if let parent = split.parent, var children = parent.children {
            if let index = children.firstIndex(where: { $0 === leaf }) {
                children[index] = split
                parent.children = children
            }
        } else {
            root = split
        }

        self.focusedSessionID = newSession.id
        objectWillChange.send()
    }

    /// Removes the focused leaf. If it has a sibling, the sibling takes its
    /// place and becomes focused; if it is the root, nothing is removed and
    /// the caller closes the whole tab.
    @discardableResult
    func closeFocusedPane() -> TerminalSession? {
        guard let leaf = pane(containing: focusedSessionID) else { return nil }
        return remove(leaf)
    }

    @discardableResult
    private func remove(_ leaf: Pane) -> TerminalSession? {
        guard let parent = leaf.parent else { return nil }

        guard let sibling = parent.children?.first(where: { $0 !== leaf }) else { return nil }
        if let session = leaf.session {
            unsubscribe(session)
            session.close()
        }

        if let grandparent = parent.parent {
            if let index = grandparent.children?.firstIndex(where: { $0 === parent }) {
                grandparent.children?[index] = sibling
            }
            sibling.parent = grandparent
        } else {
            root = sibling
            sibling.parent = nil
        }

        let next = firstLeaf(of: sibling)
        if let next {
            focusedSessionID = next.id
        }
        objectWillChange.send()
        return next
    }

    private func firstLeaf(of pane: Pane) -> TerminalSession? {
        if let session = pane.session { return session }
        return pane.children?.first.flatMap { firstLeaf(of: $0) }
    }

    // MARK: - Focus

    func focus(sessionID: UUID) {
        guard focusedSessionID != sessionID, allSessions.contains(where: { $0.id == sessionID }) else { return }
        focusedSessionID = sessionID
    }

    func focus(direction: PaneDirection) {
        guard let target = neighbor(of: focusedSessionID, direction: direction) else { return }
        focusedSessionID = target.id
    }

    func focusNext() {
        let sessions = allSessions
        guard let index = sessions.firstIndex(where: { $0.id == focusedSessionID }) else { return }
        focusedSessionID = sessions[(index + 1) % sessions.count].id
    }

    func focusPrevious() {
        let sessions = allSessions
        guard let index = sessions.firstIndex(where: { $0.id == focusedSessionID }) else { return }
        focusedSessionID = sessions[(index - 1 + sessions.count) % sessions.count].id
    }

    private func neighbor(of sessionID: UUID, direction: PaneDirection) -> TerminalSession? {
        guard let leaf = pane(containing: sessionID) else { return nil }

        var current: Pane? = leaf
        while let node = current, let parent = node.parent,
              let axis = parent.axis, let children = parent.children, children.count == 2 {
            let fromIndex = children[0] === node ? 0 : 1

            var target: Pane?
            switch (axis, direction) {
            case (.horizontal, .right): if fromIndex == 0 { target = children[1] }
            case (.horizontal, .left): if fromIndex == 1 { target = children[0] }
            case (.vertical, .down): if fromIndex == 0 { target = children[1] }
            case (.vertical, .up): if fromIndex == 1 { target = children[0] }
            default: break
            }

            if let target {
                switch direction {
                case .right, .down: return firstLeaf(of: target)
                case .left, .up: return lastLeaf(of: target)
                }
            }
            current = parent
        }
        return nil
    }

    private func lastLeaf(of pane: Pane) -> TerminalSession? {
        if let session = pane.session { return session }
        return pane.children?.last.flatMap { lastLeaf(of: $0) }
    }
}
