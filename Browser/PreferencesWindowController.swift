import AppKit
import WebKit

final class PreferencesWindowController: NSWindowController {
    private let searchPopup = NSPopUpButton()
    private let status = NSTextField(labelWithString: "")
    private let favoritesCheck = NSButton(checkboxWithTitle: "Show favorites on Start Page", target: nil, action: nil)
    private let recentCheck = NSButton(checkboxWithTitle: "Show recently visited sites on Start Page", target: nil, action: nil)
    private var siteSettingsController: SiteSettingsWindowController?

    init() {
        let controller = NSViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AINCRAD Browser Settings"
        window.contentViewController = controller
        super.init(window: window)
        window.center()
        buildUI(in: controller)
        window.setContentSize(NSSize(width: 540, height: 470))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(in controller: NSViewController) {
        let root = NSView(); controller.view = root
        let title = NSTextField(labelWithString: "AINCRAD // SETTINGS"); title.font = AINCRADTheme.displayFont(size: 22); title.textColor = AINCRADTheme.panelText
        let searchLabel = NSTextField(labelWithString: "Default search engine")
        searchPopup.addItems(withTitles: ["DuckDuckGo", "Google", "Bing"])
        let current = BrowserStore.shared.searchTemplate
        searchPopup.selectItem(at: current.contains("google") ? 1 : current.contains("bing") ? 2 : 0)
        searchPopup.target = self; searchPopup.action = #selector(searchChanged)

        let passwords = NSButton(title: "Open Apple Passwords…", target: self, action: #selector(openPasswords))
        passwords.bezelStyle = .rounded
        let passwordNote = NSTextField(wrappingLabelWithString: "AINCRAD Browser uses macOS WebKit, so compatible website login fields, passkeys, and verification codes are handled by the system Passwords experience. AINCRAD Browser never reads or stores those secrets itself.")
        passwordNote.textColor = .secondaryLabelColor

        favoritesCheck.state = BrowserStore.shared.showFavoritesOnStartPage ? .on : .off; recentCheck.state = BrowserStore.shared.showRecentOnStartPage ? .on : .off
        favoritesCheck.target = self; favoritesCheck.action = #selector(startPageChanged); recentCheck.target = self; recentCheck.action = #selector(startPageChanged)
        let sitePermissions = NSButton(title: "Manage Website Permissions…", target: self, action: #selector(showSitePermissions))
        let defaultBrowser = NSButton(title: "Open Default Browser Settings…", target: self, action: #selector(openDefaultBrowserSettings))
        let browserActions = NSStackView(views: [sitePermissions, defaultBrowser]); browserActions.spacing = 8

        let clearWebsiteData = NSButton(title: "Clear Website Data…", target: self, action: #selector(clearWebsiteData))
        clearWebsiteData.bezelStyle = .rounded
        let clearHistory = NSButton(title: "Clear AINCRAD Browser History…", target: self, action: #selector(clearHistory))
        clearHistory.bezelStyle = .rounded
        let actions = NSStackView(views: [clearWebsiteData, clearHistory]); actions.orientation = .horizontal; actions.spacing = 8
        status.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, searchLabel, searchPopup, favoritesCheck, recentCheck, separator(), passwords, passwordNote, browserActions, separator(), actions, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            searchPopup.widthAnchor.constraint(equalToConstant: 210), passwordNote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

    @objc private func searchChanged() {
        BrowserStore.shared.searchTemplate = ["https://duckduckgo.com/?q=%@", "https://www.google.com/search?q=%@", "https://www.bing.com/search?q=%@"][searchPopup.indexOfSelectedItem]
        status.stringValue = "Search engine updated."
    }

    @objc private func startPageChanged() {
        BrowserStore.shared.showFavoritesOnStartPage = favoritesCheck.state == .on
        BrowserStore.shared.showRecentOnStartPage = recentCheck.state == .on
        status.stringValue = "Start Page updated."
    }

    @objc private func showSitePermissions() {
        let controller = siteSettingsController ?? SiteSettingsWindowController(); siteSettingsController = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openDefaultBrowserSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension") { NSWorkspace.shared.open(url) }
    }

    @objc private func openPasswords() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Passwords.app"), configuration: .init()) { _, error in
            if let error { DispatchQueue.main.async { self.status.stringValue = error.localizedDescription } }
        }
    }

    @objc private func clearHistory() {
        let alert = NSAlert(); alert.messageText = "Clear AINCRAD Browser history?"; alert.addButton(withTitle: "Clear"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { BrowserStore.shared.clearHistory(); status.stringValue = "History cleared." }
    }

    @objc private func clearWebsiteData() {
        let alert = NSAlert(); alert.messageText = "Clear all website data?"; alert.informativeText = "This signs you out of websites and removes cookies, local storage, and caches. Apple Passwords are not deleted."; alert.addButton(withTitle: "Clear Website Data"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: types) { records in
            store.removeData(ofTypes: types, for: records) { DispatchQueue.main.async { self.status.stringValue = "Website data cleared." } }
        }
    }
}

