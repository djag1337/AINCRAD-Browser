import AppKit
import UniformTypeIdentifiers
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    private var preferencesController: PreferencesWindowController?
    private var settingsController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AINCRADTheme.start()
        BrowserStore.shared.migrateToSharedPrefs()
        BrowserFeatures.shared.start()
        buildMenus()
        NotificationCenter.default.addObserver(self, selector: #selector(publishLink), name: .browserDataChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(browserStateChanged), name: .browserWindowStateChanged, object: nil)
        if BrowserStore.shared.savedSession.windows.isEmpty || !BrowserPrefsModel.shared.prefs.restoreSession {
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
                browser.newTab(focusAddress: false); browser.openURL(target)
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
    /// With AINCRAD installed the browser's settings are a page of AINCRAD Settings; otherwise the same page opens here.
    @objc private func showSettings(_ sender: Any?) {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.djag.aincrad") != nil, let url = URL(string: "aincrad://settings/browser") {
            NSWorkspace.shared.open(url); return
        }
        if settingsController == nil {
            let host = NSHostingController(rootView: Form { BrowserPrefsForm() }.formStyle(.grouped))
            let window = NSWindow(contentViewController: host)
            window.title = "AINCRAD Browser Settings"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 560, height: 680))
            window.isReleasedWhenClosed = false
            window.center()
            settingsController = NSWindowController(window: window)
        }
        settingsController?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showPrivacyData(_ sender: Any?) {
        let controller = preferencesController ?? PreferencesWindowController()
        preferencesController = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleReader(_ sender: Any?) { currentBrowser()?.toggleReader() }
    @objc private func goBackMenu(_ sender: Any?) { currentBrowser()?.goBackAction() }
    @objc private func goForwardMenu(_ sender: Any?) { currentBrowser()?.goForwardAction() }
    @objc private func reloadMenu(_ sender: Any?) { currentBrowser()?.reloadAction(hard: false) }
    @objc private func hardReloadMenu(_ sender: Any?) { currentBrowser()?.reloadAction(hard: true) }
    @objc private func stopMenu(_ sender: Any?) { currentBrowser()?.stopAction() }
    @objc private func nextTabMenu(_ sender: Any?) { currentBrowser()?.nextTab(by: 1) }
    @objc private func previousTabMenu(_ sender: Any?) { currentBrowser()?.nextTab(by: -1) }
    @objc private func selectTabMenu(_ sender: NSMenuItem) { currentBrowser()?.selectTabNumber(sender.tag) }
    @objc private func closeOthersMenu(_ sender: Any?) { if let b = currentBrowser() { b.closeOtherTabs(keeping: b.currentIndex) } }
    @objc private func closeRightMenu(_ sender: Any?) { if let b = currentBrowser() { b.closeTabsToRight(of: b.currentIndex) } }
    @objc private func findNextMenu(_ sender: Any?) { currentBrowser()?.findAgain(backwards: false) }
    @objc private func findPreviousMenu(_ sender: Any?) { currentBrowser()?.findAgain(backwards: true) }
    @objc private func closeWindowMenu(_ sender: Any?) { NSApp.keyWindow?.performClose(nil) }
    @objc private func showShortcuts(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Keyboard shortcuts"
        alert.informativeText = """
        ⌘T new tab · ⌘W close tab · ⇧⌘T reopen closed tab · ⇧⌘W close window
        ⌃Tab / ⇧⌘] next tab · ⌃⇧Tab / ⇧⌘[ previous tab · ⌘1…⌘8 tab by number · ⌘9 last tab
        ⌘L address bar · ⌘R reload · ⌥⌘R reload without cache · ⌘. stop · ⌘[ back · ⌘] forward
        ⌘F find · ⌘G next match · ⇧⌘G previous match · ⇧⌘R reader mode
        ⌘D bookmark · ⌘B bookmarks · ⌘Y history · ⌘J downloads · ⌘S sidebar
        ⌘+ ⌘- ⌘0 zoom · ⌘, settings (AINCRAD Settings › Browser)
        Middle-click or the ✕ closes a tab; right-click a tab for more.
        """
        alert.runModal()
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
        appMenu.addItem(withTitle: "Privacy & Data…", action: #selector(showPrivacyData(_:)), keyEquivalent: "").target = self
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
        add(file, "Close Window", #selector(closeWindowMenu(_:)), "w", [.command, .shift])
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
        let findNext = NSMenuItem(title: "Find Next", action: #selector(findNextMenu(_:)), keyEquivalent: "g"); findNext.target = self; edit.addItem(findNext)
        let findPrev = NSMenuItem(title: "Find Previous", action: #selector(findPreviousMenu(_:)), keyEquivalent: "g"); findPrev.keyEquivalentModifierMask = [.command, .shift]; findPrev.target = self; edit.addItem(findPrev)
        edit.addItem(withTitle: "Copy Page Link", action: #selector(copyLink(_:)), keyEquivalent: "").target = self

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View"); viewItem.submenu = view
        view.addItem(withTitle: "Show Address Bar", action: #selector(focusAddress(_:)), keyEquivalent: "l").target = self
        view.addItem(withTitle: "Toggle Sidebar", action: #selector(toggleSidebar(_:)), keyEquivalent: "s").target = self
        let reader = view.addItem(withTitle: "Reader Mode", action: #selector(toggleReader(_:)), keyEquivalent: "r")
        reader.keyEquivalentModifierMask = [.command, .shift]; reader.target = self
        view.addItem(.separator())
        view.addItem(withTitle: "Actual Size", action: #selector(resetZoom(_:)), keyEquivalent: "0").target = self
        view.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "+").target = self
        view.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-").target = self
        view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f").keyEquivalentModifierMask = [.control, .command]

        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods; item.target = self; item.tag = tag
        }
        let tabItem = NSMenuItem(); main.addItem(tabItem)
        let tab = NSMenu(title: "Tab"); tabItem.submenu = tab
        add(tab, "Next Tab", #selector(nextTabMenu(_:)), "]", [.command, .shift])
        add(tab, "Previous Tab", #selector(previousTabMenu(_:)), "[", [.command, .shift])
        add(tab, "Next Tab (Control-Tab)", #selector(nextTabMenu(_:)), "\t", [.control])
        add(tab, "Previous Tab (Control-Shift-Tab)", #selector(previousTabMenu(_:)), "\t", [.control, .shift])
        tab.addItem(.separator())
        for n in 1...9 { add(tab, n == 9 ? "Last Tab" : "Tab \(n)", #selector(selectTabMenu(_:)), "\(n)", [.command], tag: n) }
        tab.addItem(.separator())
        tab.addItem(withTitle: "Duplicate Tab", action: #selector(duplicateTab(_:)), keyEquivalent: "").target = self
        tab.addItem(withTitle: "Pin or Unpin Tab", action: #selector(togglePin(_:)), keyEquivalent: "").target = self
        tab.addItem(withTitle: "Close Other Tabs", action: #selector(closeOthersMenu(_:)), keyEquivalent: "").target = self
        tab.addItem(withTitle: "Close Tabs to the Right", action: #selector(closeRightMenu(_:)), keyEquivalent: "").target = self
        tab.addItem(.separator())
        add(tab, "Move Tab Left", #selector(moveTabLeft(_:)), "[", [.command, .option])
        add(tab, "Move Tab Right", #selector(moveTabRight(_:)), "]", [.command, .option])

        let historyItem = NSMenuItem(); main.addItem(historyItem)
        let history = NSMenu(title: "History"); historyItem.submenu = history
        add(history, "Back", #selector(goBackMenu(_:)), "[")
        add(history, "Forward", #selector(goForwardMenu(_:)), "]")
        add(history, "Reload Page", #selector(reloadMenu(_:)), "r")
        add(history, "Reload Without Cache", #selector(hardReloadMenu(_:)), "r", [.command, .option])
        add(history, "Stop Loading", #selector(stopMenu(_:)), ".")
        history.addItem(.separator())
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

        let helpItem = NSMenuItem(); main.addItem(helpItem)
        let help = NSMenu(title: "Help"); helpItem.submenu = help; NSApp.helpMenu = help
        help.addItem(withTitle: "Keyboard Shortcuts", action: #selector(showShortcuts(_:)), keyEquivalent: "/").target = self
    }
}

