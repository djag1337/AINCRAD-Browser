import Foundation

final class BrowserStore {
    static let shared = BrowserStore()
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private static let profileKeys = ["history", "bookmarks", "recentlyClosed", "session", "sitePermissions", "searchTemplate", "showFavoritesOnStartPage", "showRecentOnStartPage"]

    private(set) var history: [HistoryEntry]
    private(set) var bookmarks: [Bookmark]
    private(set) var recentlyClosed: [TabState]
    private(set) var savedSession: SessionState
    private(set) var sitePermissions: [String: SitePermissions]

    private init() {
        Self.migrateGlassProfileIfNeeded()
        history = Self.decode([HistoryEntry].self, key: "history") ?? []
        bookmarks = Self.decode([Bookmark].self, key: "bookmarks") ?? []
        recentlyClosed = Self.decode([TabState].self, key: "recentlyClosed") ?? []
        savedSession = Self.decode(SessionState.self, key: "session") ?? .empty
        sitePermissions = Self.decode([String: SitePermissions].self, key: "sitePermissions") ?? [:]
    }

    /// The product rename uses a new bundle identifier. Copy the prior Glass defaults once so
    /// existing bookmarks, history, permissions and the last session remain available.
    private static func migrateGlassProfileIfNeeded() {
        let current = UserDefaults.standard
        guard current.bool(forKey: "didMigrateGlassProfile") == false else { return }
        if let legacy = UserDefaults(suiteName: "local.codex.Glass") {
            for key in profileKeys where current.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) { current.set(value, forKey: key) }
            }
        }
        current.set(true, forKey: "didMigrateGlassProfile")
    }

    var searchTemplate: String {
        get { defaults.string(forKey: "searchTemplate") ?? "https://duckduckgo.com/?q=%@" }
        set { defaults.set(newValue, forKey: "searchTemplate") }
    }

    var showFavoritesOnStartPage: Bool {
        get { defaults.object(forKey: "showFavoritesOnStartPage") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showFavoritesOnStartPage"); NotificationCenter.default.post(name: .startPageSettingsChanged, object: nil) }
    }

    var showRecentOnStartPage: Bool {
        get { defaults.object(forKey: "showRecentOnStartPage") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showRecentOnStartPage"); NotificationCenter.default.post(name: .startPageSettingsChanged, object: nil) }
    }

    func permissions(for host: String) -> SitePermissions { sitePermissions[host] ?? SitePermissions() }
    func setPermissions(_ permissions: SitePermissions, for host: String) {
        sitePermissions[host] = permissions; save(sitePermissions, key: "sitePermissions")
        NotificationCenter.default.post(name: .sitePermissionsChanged, object: nil)
    }
    func clearPermissions(for host: String) {
        sitePermissions.removeValue(forKey: host); save(sitePermissions, key: "sitePermissions")
        NotificationCenter.default.post(name: .sitePermissionsChanged, object: nil)
    }

    func recordVisit(url: URL, title: String) {
        guard url.scheme == "http" || url.scheme == "https" else { return }
        history.insert(HistoryEntry(url: url.absoluteString, title: title, visitedAt: Date()), at: 0)
        if history.count > 2_000 { history.removeLast(history.count - 2_000) }
        save(history, key: "history")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func addBookmark(url: URL, title: String) {
        guard !bookmarks.contains(where: { $0.url == url.absoluteString }) else { return }
        bookmarks.insert(Bookmark(url: url.absoluteString, title: title, createdAt: Date()), at: 0)
        save(bookmarks, key: "bookmarks")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func addBookmarks(_ imported: [Bookmark]) {
        let existing = Set(bookmarks.map(\.url))
        bookmarks.append(contentsOf: imported.filter { !existing.contains($0.url) })
        save(bookmarks, key: "bookmarks")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
        save(bookmarks, key: "bookmarks")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func removeHistory(id: UUID) {
        history.removeAll { $0.id == id }
        save(history, key: "history")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func clearHistory() {
        history.removeAll(); save(history, key: "history")
        NotificationCenter.default.post(name: .browserDataChanged, object: nil)
    }

    func rememberClosed(_ tab: TabState) {
        recentlyClosed.insert(tab, at: 0)
        if recentlyClosed.count > 20 { recentlyClosed.removeLast() }
        save(recentlyClosed, key: "recentlyClosed")
    }

    func popClosed() -> TabState? {
        guard !recentlyClosed.isEmpty else { return nil }
        let tab = recentlyClosed.removeFirst(); save(recentlyClosed, key: "recentlyClosed"); return tab
    }

    func saveSession(_ session: SessionState) { savedSession = session; save(session, key: "session") }

    private func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? encoder.encode(value) { defaults.set(data, forKey: key) }
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

extension Notification.Name {
    static let browserDataChanged = Notification.Name("AINCRADBrowserDataChanged")
    static let sitePermissionsChanged = Notification.Name("AINCRADSitePermissionsChanged")
    static let startPageSettingsChanged = Notification.Name("AINCRADStartPageSettingsChanged")
}
