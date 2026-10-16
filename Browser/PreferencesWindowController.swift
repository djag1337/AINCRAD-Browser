import AppKit
import WebKit

final class PreferencesWindowController: NSWindowController {
    private let status = NSTextField(labelWithString: "")
    private var siteSettingsController: SiteSettingsWindowController?

    init() {
        let controller = NSViewController()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 380), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Privacy & Data"
        window.contentViewController = controller
        super.init(window: window)
        window.center()
        buildUI(in: controller)
        window.setContentSize(NSSize(width: 540, height: 380))
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI(in controller: NSViewController) {
        let root = NSView(); controller.view = root
        let title = NSTextField(labelWithString: "PRIVACY & DATA"); title.font = AINCRADTheme.displayFont(size: 22); title.textColor = AINCRADTheme.panelText

        let passwords = NSButton(title: "Open Apple Passwords…", target: self, action: #selector(openPasswords))
        passwords.bezelStyle = .rounded
        let passwordNote = NSTextField(wrappingLabelWithString: "AINCRAD Browser uses macOS WebKit, so compatible website login fields, passkeys, and verification codes are handled by the system Passwords experience. AINCRAD Browser never reads or stores those secrets itself.")
        passwordNote.textColor = .secondaryLabelColor

        let sitePermissions = NSButton(title: "Manage Website Permissions…", target: self, action: #selector(showSitePermissions))
        let defaultBrowser = NSButton(title: "Open Default Browser Settings…", target: self, action: #selector(openDefaultBrowserSettings))
        let browserActions = NSStackView(views: [sitePermissions, defaultBrowser]); browserActions.spacing = 8

        let clearWebsiteData = NSButton(title: "Clear Website Data…", target: self, action: #selector(clearWebsiteData))
        clearWebsiteData.bezelStyle = .rounded
        let clearHistory = NSButton(title: "Clear AINCRAD Browser History…", target: self, action: #selector(clearHistory))
        clearHistory.bezelStyle = .rounded
        let actions = NSStackView(views: [clearWebsiteData, clearHistory]); actions.orientation = .horizontal; actions.spacing = 8
        status.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, passwords, passwordNote, browserActions, separator(), actions, status])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 30), stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -30),
            passwordNote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }

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

