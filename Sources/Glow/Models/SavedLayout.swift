import Foundation

struct SavedTab: Codable, Hashable {
    var title: String
    var colorHex: String
    var folder: String
    var startCommand: String?
    /// The tab's split-pane tree; nil means a single pane (older layouts).
    var panes: SavedPane?
}

/// A saved split-pane tree. A leaf has `folder`/`title`/`colorHex`/
/// `startCommand` and no `axis`/`children`; a branch has `axis` ("h"/"v")
/// and two `children`. `panes` is absent in layouts saved before splits
/// were persisted, which decode as a single-pane tab.
struct SavedPane: Codable, Hashable {
    var axis: String?
    var children: [SavedPane]?
    var folder: String?
    var title: String?
    var colorHex: String?
    var startCommand: String?
}

struct SavedLayout: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var tabs: [SavedTab]

    init(name: String, tabs: [SavedTab]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.tabs = tabs
    }
}
