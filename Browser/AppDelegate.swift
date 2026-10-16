import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    private var preferencesController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AINCRADTheme.start()
        buildMenus()
        NotificationCenter.default.addObserver(self, selector: #selector(publishLink), name: .browserDataChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(browserStateChanged), name: .browserWindowStateChanged, object: nil)
        if BrowserStore.shared.savedSession.windows.isEmpty {
            openWindow(privateMode: false)
        } else {
            for state in BrowserStore.shared.savedSession.windows {
                openWindow(privateMode: false, restoring: state)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        publishLink()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        saveSession()
        AINCRADLink.clearTabs()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == "aincrad-browser" { handleLink(url) }
            else if let browser = currentBrowser() ?? windows.last(where: { !$0.browser.privateMode })?.browser { browser.openURL(url) }
            else { openWindow(privateMode: false, url: url) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// aincrad-browser://open?url=…  ·  tab?window=W&index=I  ·  new  ·  private
    private func handleLink(_ url: URL) {
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { q.first { $0.name == name }?.value }
        switch url.host {
        case "open":
            guard let target = value("url").flatMap(URL.init(string:)), ["http", "https"].contains(target.scheme ?? "") else { return }
            if let browser = windows.last(where: { !$0.browser.privateMode })?.browser {
                browser.newTab(); browser.openURL(target)
                browser.view.window?.makeKeyAndOrderFront(nil)
            } else { openWindow(privateMode: false, url: target) }
        case "tab":
            let normal = windows.filter { !$0.browser.privateMode }
            guard let w = value("window").flatMap(Int.init), let i = value("index").flatMap(Int.init), normal.indices.contains(w) else { return }
            normal[w].browser.showTab(at: i)
            normal[w].window?.makeKeyAndOrderFront(nil)
        case "new": newTab(nil)
        case "private": openWindow(privateMode: true)
        default: break
        }
    }

    /// Tells AINCRAD what's open (normal windows only, in the order AINCRAD numbers them).
    @objc private func publishLink() {
        AINCRADLink.publish { [weak self] in
            (self?.windows.filter { !$0.browser.privateMode } ?? []).enumerated().map { ($0.offset, $0.element.windowState()) }
        }
    }

    @discardableResult
    func openWindow(privateMode: Bool, url: URL? = nil, restoring: WindowState? = nil) -> BrowserWindowController {
        let controller = BrowserWindowController(privateMode: privateMode, restoredState: restoring)
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        controller.showWindow(nil)
        if let url { controller.browser.openURL(url) }
        return controller
    }

    private func currentBrowser() -> BrowserViewController? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)?.browser
    }

    private func saveSession() {
        let states = windows.filter { !$0.browser.privateMode }.map { $0.windowState() }
        BrowserStore.shared.saveSession(SessionState(windows: states))
    }

    @objc private func browserStateChanged() {
        guard !windows.isEmpty else { return }
        saveSession()
        publishLink()
    }

    @objc private func newWindow(_ sender: Any?) { openWindow(privateMode: false) }
    @objc private func newPrivateWindow(_ sender: Any?) { openWindow(privateMode: true) }
    @objc private func newTab(_ sender: Any?) {
        if let browser = currentBrowser() { browser.newTab() }
        else { openWindow(privateMode: false) }
    }
    @objc private func closeTab(_ sender: Any?) { currentBrowser()?.closeCurrentTab() }
    @objc private func reopenTab(_ sender: Any?) { currentBrowser()?.reopenClosedTab() }
    @objc private func focusAddress(_ sender: Any?) { currentBrowser()?.focusAddressBar() }
    @objc private func find(_ sender: Any?) { currentBrowser()?.showFind() }
    @objc private func toggleSidebar(_ sender: Any?) { currentBrowser()?.toggleSidebar() }
    @objc private func showHistory(_ sender: Any?) { currentBrowser()?.showSidebar(section: .history) }
    @objc private func showBookmarks(_ sender: Any?) { currentBrowser()?.showSidebar(section: .bookmarks) }
    @objc private func addBookmark(_ sender: Any?) { currentBrowser()?.bookmarkCurrentPage() }
    @objc private func duplicateTab(_ sender: Any?) { currentBrowser()?.duplicateCurrentTab() }
    @objc private func togglePin(_ sender: Any?) { currentBrowser()?.togglePinCurrentTab() }
    @objc private func moveTabLeft(_ sender: Any?) { currentBrowser()?.moveCurrentTab(by: -1) }
    @objc private func moveTabRight(_ sender: Any?) { currentBrowser()?.moveCurrentTab(by: 1) }
    @objc private func zoomIn(_ sender: Any?) { currentBrowser()?.zoom(by: 0.1) }
    @objc private func zoomOut(_ sender: Any?) { currentBrowser()?.zoom(by: -0.1) }
    @objc private func resetZoom(_ sender: Any?) { currentBrowser()?.resetZoom() }
    @objc private func printPage(_ sender: Any?) { currentBrowser()?.printPage() }
    @objc private func savePDF(_ sender: Any?) { currentBrowser()?.savePageAsPDF() }
    @objc private func copyLink(_ sender: Any?) { currentBrowser()?.copyPageLink() }
    @objc private func showDownloads(_ sender: Any?) { DownloadManager.shared.showWindow() }
    @objc private func showSettings(_ sender: Any?) {
        let controller = preferencesController ?? PreferencesWindowController()
        preferencesController = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func openPasswords(_ sender: Any?) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Passwords.app"))
    }
    @objc private func importBookmarks(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.html]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let items = try BookmarkTransfer.importHTML(from: url); BrowserStore.shared.addBookmarks(items)
            let alert = NSAlert(); alert.messageText = "Imported \(items.count) bookmarks"; alert.runModal()
        } catch { NSAlert(error: error).runModal() }
    }
    @objc private func exportBookmarks(_ sender: Any?) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.html]; panel.nameFieldStringValue = "AINCRAD Browser Bookmarks.html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try BookmarkTransfer.exportHTML(BrowserStore.shared.bookmarks, to: url) } catch { NSAlert(error: error).runModal() }
    }

    private func buildMenus() {
        let main = NSMenu()
        NSApp.mainMenu = main

        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "AINCRAD Browser"); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About AINCRAD Browser", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit AINCRAD Browser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem(); main.addItem(fileItem)
        let file = NSMenu(title: "File"); fileItem.submenu = file
        file.addItem(withTitle: "New Window", action: #selector(newWindow(_:)), keyEquivalent: "n").target = self
        let privateItem = file.addItem(withTitle: "New Private Window", action: #selector(newPrivateWindow(_:)), keyEquivalent: "n")
        privateItem.keyEquivalentModifierMask = [.command, .shift]; privateItem.target = self
        file.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t").target = self
        file.addItem(withTitle: "Close Tab", action: #selector(closeTab(_:)), keyEquivalent: "w").target = self
        let reopen = file.addItem(withTitle: "Reopen Closed Tab", action: #selector(reopenTab(_:)), keyEquivalent: "t")
        reopen.keyEquivalentModifierMask = [.command, .shift]; reopen.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Save Page as PDF…", action: #selector(savePDF(_:)), keyEquivalent: "").target = self
        file.addItem(withTitle: "Print…", action: #selector(printPage(_:)), keyEquivalent: "p").target = self

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Find", action: #selector(find(_:)), keyEquivalent: "f").target = self
        edit.addItem(withTitle: "Copy Page Link", action: #selector(copyLink(_:)), keyEquivalent: "").target = self

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View"); viewItem.submenu = view
        view.addItem(withTitle: "Show Address Bar", action: #selector(focusAddress(_:)), keyEquivalent: "l").target = self
        view.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "s").target = self
        view.addItem(.separator())
        view.addItem(withTitle: "Actual Size", action: #selector(resetZoom(_:)), keyEquivalent: "0").target = self
        view.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+").target = self
        view.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-").target = self
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.control, .command]

        let tabItem = NSMenuItem(); main.addItem(tabItem)
        let tab = NSMenu(title: "Tab"); tabItem.submenu = tab
        tab.addItem(withTitle: "Duplicate Tab", action: #selector(duplicateTab(_:)), keyEquivalent: "").target = self
        tab.addItem(withTitle: "Pin or Unpin Tab", action: #selector(togglePin(_:)), keyEquivalent: "").target = self
        tab.addItem(.separator())
        let left = tab.addItem(withTitle: "Move Tab Left", action: #selector(moveTabLeft(_:)), keyEquivalent: "["); left.keyEquivalentModifierMask = [.command, .shift]; left.target = self
        let right = tab.addItem(withTitle: "Move Tab Right", action: #selector(moveTabRight(_:)), keyEquivalent: "]"); right.keyEquivalentModifierMask = [.command, .shift]; right.target = self

        let historyItem = NSMenuItem(); main.addItem(historyItem)
        let history = NSMenu(title: "History"); historyItem.submenu = history
        history.addItem(withTitle: "Show History", action: #selector(showHistory(_:)), keyEquivalent: "y").target = self
        history.addItem(withTitle: "Show Downloads", action: #selector(showDownloads(_:)), keyEquivalent: "j").target = self

        let bookmarksItem = NSMenuItem(); main.addItem(bookmarksItem)
        let bookmarks = NSMenu(title: "Bookmarks"); bookmarksItem.submenu = bookmarks
        bookmarks.addItem(withTitle: "Add Bookmark", action: #selector(addBookmark(_:)), keyEquivalent: "d").target = self
        bookmarks.addItem(withTitle: "Show Bookmarks", action: #selector(showBookmarks(_:)), keyEquivalent: "b").target = self
        bookmarks.addItem(.separator())
        bookmarks.addItem(withTitle: "Import Bookmarks…", action: #selector(importBookmarks(_:)), keyEquivalent: "").target = self
        bookmarks.addItem(withTitle: "Export Bookmarks…", action: #selector(exportBookmarks(_:)), keyEquivalent: "").target = self

        let passwordsItem = NSMenuItem(); main.addItem(passwordsItem)
        let passwords = NSMenu(title: "Passwords"); passwordsItem.submenu = passwords
        passwords.addItem(withTitle: "Open Apple Passwords…", action: #selector(openPasswords(_:)), keyEquivalent: "").target = self

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let window = NSMenu(title: "Window"); windowItem.submenu = window; NSApp.windowsMenu = window
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
    }
}

