import Foundation

struct TabState: Codable, Equatable {
    var url: String
    var title: String
    var pinned: Bool = false
}

struct WindowState: Codable {
    var tabs: [TabState]
    var selectedIndex: Int
    var frame: String?

    init(tabs: [TabState], selectedIndex: Int, frame: String? = nil) {
        self.tabs = tabs; self.selectedIndex = selectedIndex; self.frame = frame
    }
}

struct SessionState: Codable {
    var windows: [WindowState]
    static let empty = SessionState(windows: [])
}

struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    let url: String
    let title: String
    let visitedAt: Date
}

struct Bookmark: Codable, Identifiable {
    var id = UUID()
    let url: String
    let title: String
    let createdAt: Date
}

enum SidebarSection { case bookmarks, history }

enum SitePermission: String, Codable, CaseIterable { case ask, allow, deny }

struct SitePermissions: Codable {
    var camera: SitePermission = .ask
    var microphone: SitePermission = .ask
}

protocol ExtensionProvider {
    var displayName: String { get }
    func prepare() async throws
}

struct NoExtensionsProvider: ExtensionProvider {
    let displayName = "Extensions unavailable"
    func prepare() async throws { }
}

