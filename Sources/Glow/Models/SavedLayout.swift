import Foundation

struct SavedTab: Codable, Hashable {
    var title: String
    var colorHex: String
    var folder: String
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
