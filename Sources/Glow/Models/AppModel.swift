import AppKit
import Combine
import Foundation

final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: GlowSettings {
        didSet {
            NotificationCenter.default.post(name: .glowSettingsChanged, object: nil)
            schedulePersist()
        }
    }
    @Published var recentFolders: [String] {
        didSet { schedulePersist() }
    }
    @Published var layouts: [SavedLayout] {
        didSet { schedulePersist() }
    }

    var theme: GlowTheme { GlowTheme.forName(settings.themeName) }

    private var persistWorkItem: DispatchWorkItem?
    private var shouldRestoreOnLaunch = true
    private let stateURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let supportDir = base.appendingPathComponent("Glow", isDirectory: true)
        stateURL = supportDir.appendingPathComponent("glow-state.json")
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        settings = GlowSettings()
        recentFolders = []
        layouts = []
        load()
    }

    /// Called by the first window only: restore the last layout on launch if enabled.
    func consumeRestoreOnLaunch() -> Bool {
        let should = shouldRestoreOnLaunch && settings.openLastLayoutOnLaunch && !layouts.isEmpty
        shouldRestoreOnLaunch = false
        return should
    }

    func addRecent(_ path: String) {
        var list = recentFolders.filter { $0 != path }
        list.insert(path, at: 0)
        recentFolders = Array(list.prefix(12))
    }

    func removeRecent(_ path: String) {
        recentFolders.removeAll { $0 == path }
    }

    func addLayout(_ layout: SavedLayout) {
        var list = layouts.filter { $0.id != layout.id }
        list.append(layout)
        layouts = list
    }

    func removeLayout(id: UUID) {
        layouts.removeAll { $0.id == id }
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else { return }
        settings = state.settings
        recentFolders = state.recentFolders
        layouts = state.layouts
    }

    func persistNow() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        let state = PersistedState(settings: settings, recentFolders: recentFolders, layouts: layouts)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    private func schedulePersist() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.persistNow() }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }
}

struct PersistedState: Codable {
    var settings: GlowSettings
    var recentFolders: [String]
    var layouts: [SavedLayout]
}

extension Notification.Name {
    static let glowSettingsChanged = Notification.Name("glowSettingsChanged")
}
