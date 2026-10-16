import AppKit

/// How AINCRAD Browser and AINCRAD talk, without being one app:
/// - The browser writes ~/Library/Application Support/AINCRAD Browser/link.json (open tabs,
///   bookmarks, recent history; never private windows) and announces changes, so AINCRAD's
///   launcher can list them.
/// - AINCRAD opens pages and switches tabs through aincrad-browser:// links.
/// - The browser announces finished downloads (file name only; never from private windows), and
///   AINCRAD shows them as SAO bubbles. The browser's ◎ button opens AINCRAD with aincrad://open.
/// Announcements are macOS distributed notifications, visible to apps on this Mac only.
enum AINCRADLink {
    static let changedName = Notification.Name("com.djag.aincrad.browser.changed")
    static let downloadName = Notification.Name("com.djag.aincrad.browser.downloadFinished")

    struct Tab: Codable { let window: Int; let index: Int; let title: String; let url: String; let selected: Bool }
    struct Item: Codable { let title: String; let url: String }
    struct Snapshot: Codable { var version = 1; let tabs: [Tab]; let bookmarks: [Item]; let history: [Item] }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AINCRAD Browser/link.json")
    }

    private static var pending: DispatchWorkItem?

    /// Writes the snapshot shortly after changes settle (tab switches come in bursts).
    static func publish(windows: @escaping () -> [(index: Int, state: WindowState)]) {
        pending?.cancel()
        let work = DispatchWorkItem {
            let store = BrowserStore.shared
            var tabs: [Tab] = []
            for (w, state) in windows() {
                for (i, t) in state.tabs.enumerated() where t.url.hasPrefix("http") {
                    tabs.append(Tab(window: w, index: i, title: t.title.isEmpty ? t.url : t.title, url: t.url, selected: i == state.selectedIndex))
                }
            }
            var seen = Set<String>()
            let history = store.history.filter { seen.insert($0.url).inserted }.prefix(20).map { Item(title: $0.title, url: $0.url) }
            let snap = Snapshot(tabs: tabs, bookmarks: store.bookmarks.prefix(40).map { Item(title: $0.title, url: $0.url) }, history: Array(history))
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snap) { try? data.write(to: fileURL, options: .atomic) }
            DistributedNotificationCenter.default().postNotificationName(changedName, object: nil, userInfo: nil, deliverImmediately: true)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Removes the snapshot when the browser quits, so AINCRAD doesn't list tabs that are gone.
    static func clearTabs() {
        guard let data = try? Data(contentsOf: fileURL), let old = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let snap = Snapshot(tabs: [], bookmarks: old.bookmarks, history: old.history)
        if let out = try? JSONEncoder().encode(snap) { try? out.write(to: fileURL, options: .atomic) }
        DistributedNotificationCenter.default().postNotificationName(changedName, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func downloadFinished(name: String, path: String?) {
        var info: [String: String] = ["name": name]
        if let path { info["path"] = path }
        DistributedNotificationCenter.default().postNotificationName(downloadName, object: nil, userInfo: info, deliverImmediately: true)
    }
}
