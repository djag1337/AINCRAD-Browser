import AppKit
import WebKit
import UniformTypeIdentifiers

final class BrowserViewController: NSViewController, NSSearchFieldDelegate, WKNavigationDelegate, WKUIDelegate {
    let privateMode: Bool
    private var tabs: [BrowserTab] = []
    private var selectedIndex = 0
    private var observations: [NSKeyValueObservation] = []

    private let sidebar = SidebarViewController()
    private let splitView = NSSplitView()
    private let mainView = NSView()
    private let webContainer = NSView()
    private let toolbar = NSVisualEffectView()
    /// The theme's panel colour, laid over the blur (a visual effect view draws over its own layer colour).
    private let toolbarTint = NSView()
    private let tabControl = SolidSegmentedControl()
    private let addressField = NSSearchField()
    private let progress = NSProgressIndicator()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let sidebarButton = NSButton()
    private let addTabButton = NSButton()
    private let bookmarkButton = NSButton()
    private let shareButton = NSButton()
    private let downloadsButton = NSButton()
    /// Opens the AINCRAD launcher (shown only when AINCRAD is installed).
    private let aincradButton = NSButton()
    private let privacyBadge = NSTextField(labelWithString: "PRIVATE")
    private let productLabel = NSTextField(labelWithString: "AINCRAD // BROWSER")
    private let accentRule = NSView()
    private var sidebarVisible = false

    init(privateMode: Bool, restoredState: WindowState?) {
        self.privateMode = privateMode
        super.init(nibName: nil, bundle: nil)
        if let restoredState, !privateMode, !restoredState.tabs.isEmpty {
            for state in restoredState.tabs { createTab(state: state, select: false) }
            selectedIndex = min(restoredState.selectedIndex, tabs.count - 1)
        } else {
            createTab(state: nil, select: false)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        configureSplitView()
        configureToolbar()
        configureWebContainer()
        selectTab(at: selectedIndex)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStartPages), name: .browserDataChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshStartPages), name: .startPageSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: AINCRADTheme.changed, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyTheme()
    }

    @objc private func themeChanged() {
        applyTheme()
        refreshStartPages()
    }

    /// Repaints the chrome in AINCRAD's current theme (called on launch and whenever it changes).
    private func applyTheme() {
        let dark = AINCRADTheme.isDark
        view.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        toolbar.material = dark ? .hudWindow : .headerView
        // Dark themes' panels are see-through, which the blur turns grey; keep them solid.
        toolbarTint.layer?.backgroundColor = (dark ? AINCRADTheme.panel.withAlphaComponent(1) : AINCRADTheme.panel).cgColor
        toolbar.layer?.borderColor = AINCRADTheme.panelBorder.cgColor
        for button in [sidebarButton, backButton, forwardButton, reloadButton, bookmarkButton, shareButton, downloadsButton, addTabButton, aincradButton] {
            AINCRADTheme.styleCircle(button)
        }
        aincradButton.image = AINCRADTheme.makeMark(size: 18)
        addressField.layer?.borderColor = AINCRADTheme.accent.withAlphaComponent(0.72).cgColor
        addressField.font = AINCRADTheme.bodyFont(size: 14)
        tabControl.selectedSegmentBezelColor = AINCRADTheme.tabBezel
        tabControl.font = AINCRADTheme.bodyFont(size: 13, weight: .semibold)
        privacyBadge.textColor = AINCRADTheme.accent
        privacyBadge.font = AINCRADTheme.displayFont(size: 9)
        productLabel.font = AINCRADTheme.displayFont(size: 11)
        productLabel.textColor = AINCRADTheme.panelText
        accentRule.layer?.backgroundColor = AINCRADTheme.accent.cgColor
        accentRule.layer?.shadowColor = AINCRADTheme.accent.cgColor
        sidebar.applyTheme()
    }

    @objc private func openAINCRAD() {
        if let url = URL(string: "aincrad://open") { NSWorkspace.shared.open(url) }
    }

    private func configureSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: view.topAnchor), splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor), splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        sidebar.view.widthAnchor.constraint(equalToConstant: 230).isActive = true
        sidebar.openURL = { [weak self] url in self?.openURL(url) }
        mainView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebar.view)
        splitView.addArrangedSubview(mainView)
        splitView.setPosition(0, ofDividerAt: 0)
        sidebar.view.isHidden = true
    }

    private func configureToolbar() {
        toolbar.material = .hudWindow
        toolbar.blendingMode = .behindWindow
        toolbar.state = .active
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(toolbar)
        toolbar.wantsLayer = true
        toolbarTint.wantsLayer = true
        toolbarTint.frame = toolbar.bounds
        toolbarTint.autoresizingMask = [.width, .height]
        toolbar.addSubview(toolbarTint)
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        toolbar.layer?.borderWidth = 1

        func symbolButton(_ button: NSButton, symbol: String, action: Selector, help: String) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
            button.bezelStyle = .texturedRounded; button.isBordered = false
            button.target = self; button.action = action; button.toolTip = help
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 32).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            AINCRADTheme.styleCircle(button)
        }
        symbolButton(sidebarButton, symbol: "sidebar.left", action: #selector(toggleSidebarAction), help: "Toggle Sidebar")
        symbolButton(backButton, symbol: "chevron.left", action: #selector(goBack), help: "Back")
        symbolButton(forwardButton, symbol: "chevron.right", action: #selector(goForward), help: "Forward")
        symbolButton(reloadButton, symbol: "arrow.clockwise", action: #selector(reloadOrStop), help: "Reload")
        symbolButton(bookmarkButton, symbol: "plus.rectangle.on.folder", action: #selector(bookmarkAction), help: "Add Bookmark")
        symbolButton(shareButton, symbol: "square.and.arrow.up", action: #selector(shareAction), help: "Share")
        symbolButton(downloadsButton, symbol: "arrow.down.circle", action: #selector(downloadsAction), help: "Downloads")
        symbolButton(addTabButton, symbol: "plus", action: #selector(addTabAction), help: "New Tab")
        symbolButton(aincradButton, symbol: "circle.circle", action: #selector(openAINCRAD), help: "Open the AINCRAD launcher")
        aincradButton.isHidden = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.djag.aincrad") == nil

        addressField.placeholderString = "Search or enter website name"
        addressField.sendsSearchStringImmediately = false
        addressField.delegate = self
        addressField.focusRingType = .none
        addressField.translatesAutoresizingMaskIntoConstraints = false
        addressField.maximumRecents = 0
        addressField.wantsLayer = true
        addressField.layer?.cornerRadius = 4
        addressField.layer?.borderWidth = 1
        addressField.layer?.borderColor = AINCRADTheme.accent.withAlphaComponent(0.72).cgColor
        addressField.font = AINCRADTheme.bodyFont(size: 14)

        tabControl.segmentStyle = .rounded
        tabControl.selectedSegmentBezelColor = AINCRADTheme.tabBezel
        tabControl.font = AINCRADTheme.bodyFont(size: 13, weight: .semibold)
        tabControl.trackingMode = .selectOne
        tabControl.target = self; tabControl.action = #selector(tabSelected)
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false; progress.isHidden = true

        privacyBadge.font = .systemFont(ofSize: 9, weight: .bold)
        privacyBadge.textColor = AINCRADTheme.accent
        privacyBadge.isHidden = !privateMode
        privacyBadge.translatesAutoresizingMaskIntoConstraints = false

        productLabel.font = AINCRADTheme.displayFont(size: 11)
        productLabel.textColor = AINCRADTheme.panelText
        productLabel.translatesAutoresizingMaskIntoConstraints = false
        productLabel.setAccessibilityLabel("AINCRAD Browser")

        accentRule.wantsLayer = true
        accentRule.layer?.backgroundColor = AINCRADTheme.accent.cgColor
        accentRule.layer?.shadowColor = AINCRADTheme.accent.cgColor
        accentRule.layer?.shadowOpacity = 0.65
        accentRule.layer?.shadowRadius = 4
        accentRule.translatesAutoresizingMaskIntoConstraints = false

        let nav = NSStackView(views: [aincradButton, sidebarButton, backButton, forwardButton, reloadButton])
        nav.orientation = .horizontal; nav.spacing = 3; nav.translatesAutoresizingMaskIntoConstraints = false
        let right = NSStackView(views: [privacyBadge, downloadsButton, shareButton, bookmarkButton])
        right.orientation = .horizontal; right.spacing = 5; right.translatesAutoresizingMaskIntoConstraints = false
        [nav, addressField, right, productLabel, tabControl, addTabButton, progress, accentRule].forEach(toolbar.addSubview)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: mainView.topAnchor), toolbar.leadingAnchor.constraint(equalTo: mainView.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: mainView.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: 98),
            nav.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 76), nav.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 12),
            addressField.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: 8), addressField.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10), addressField.heightAnchor.constraint(equalToConstant: 30),
            right.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 8), right.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12), right.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            productLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14), productLabel.centerYAnchor.constraint(equalTo: tabControl.centerYAnchor), productLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 132),
            tabControl.leadingAnchor.constraint(equalTo: productLabel.trailingAnchor, constant: 8), tabControl.trailingAnchor.constraint(equalTo: addTabButton.leadingAnchor, constant: -6), tabControl.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 9), tabControl.heightAnchor.constraint(equalToConstant: 31),
            addTabButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10), addTabButton.centerYAnchor.constraint(equalTo: tabControl.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), progress.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), progress.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor), progress.heightAnchor.constraint(equalToConstant: 2),
            accentRule.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), accentRule.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), accentRule.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor), accentRule.heightAnchor.constraint(equalToConstant: 1)
        ])
        rebuildTabControl()
    }

    private func configureWebContainer() {
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(webContainer)
        NSLayoutConstraint.activate([
            webContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor), webContainer.leadingAnchor.constraint(equalTo: mainView.leadingAnchor), webContainer.trailingAnchor.constraint(equalTo: mainView.trailingAnchor), webContainer.bottomAnchor.constraint(equalTo: mainView.bottomAnchor)
        ])
    }

    private func createTab(state: TabState?, select: Bool) {
        let tab = BrowserTab(privateMode: privateMode)
        tab.webView.navigationDelegate = self; tab.webView.uiDelegate = self
        tab.pinned = state?.pinned ?? false
        tabs.append(tab)
        if let state, let url = URL(string: state.url), url.scheme != "glass" {
            tab.webView.load(URLRequest(url: url)); tab.title = state.title
        } else {
            tab.webView.loadHTMLString(StartPage.html(privateMode: privateMode), baseURL: URL(string: "glass://start"))
        }
        if isViewLoaded { rebuildTabControl() }
        if select { selectTab(at: tabs.count - 1) }
    }

    func newTab() { createTab(state: nil, select: true); focusAddressBar() }
    @objc private func addTabAction() { newTab() }

    func closeCurrentTab() {
        guard !tabs.isEmpty else { return }
        if tabs.count == 1 { view.window?.performClose(nil); return }
        let removed = tabs.remove(at: selectedIndex)
        if !privateMode { BrowserStore.shared.rememberClosed(removed.state) }
        selectedIndex = min(selectedIndex, tabs.count - 1)
        rebuildTabControl(); selectTab(at: selectedIndex); notifyStateChanged()
    }

    func reopenClosedTab() {
        guard !privateMode, let state = BrowserStore.shared.popClosed() else { return }
        createTab(state: state, select: true)
    }

    func duplicateCurrentTab() {
        guard tabs.indices.contains(selectedIndex) else { return }
        createTab(state: tabs[selectedIndex].state, select: true)
    }

    func togglePinCurrentTab() {
        tabs[selectedIndex].pinned.toggle()
        rebuildTabControl(); notifyStateChanged()
    }

    func moveCurrentTab(by offset: Int) {
        let destination = selectedIndex + offset
        guard tabs.indices.contains(destination) else { return }
        tabs.swapAt(selectedIndex, destination)
        selectedIndex = destination
        rebuildTabControl(); selectTab(at: destination)
    }

    func zoom(by delta: CGFloat) {
        let web = tabs[selectedIndex].webView
        web.pageZoom = max(0.5, min(3, web.pageZoom + delta))
    }

    func resetZoom() { tabs[selectedIndex].webView.pageZoom = 1 }

    /// For AINCRAD's tab list.
    func showTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectTab(at: index)
    }

    @objc private func tabSelected() { selectTab(at: tabControl.selectedSegment) }

    private func selectTab(at index: Int) {
        guard tabs.indices.contains(index), isViewLoaded else { return }
        selectedIndex = index
        observations.removeAll()
        tabs.forEach { $0.webView.isHidden = true }
        webContainer.subviews.forEach { $0.removeFromSuperview() }
        let tab = tabs[index]
        tab.webView.isHidden = false
        tab.webView.translatesAutoresizingMaskIntoConstraints = false
        webContainer.addSubview(tab.webView)
        NSLayoutConstraint.activate([tab.webView.topAnchor.constraint(equalTo: webContainer.topAnchor), tab.webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor), tab.webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor), tab.webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor)])
        tabControl.selectedSegment = index
        observe(tab)
        // A focused address field won't take the new URL, so real pages take focus (start pages keep the field).
        if addressField.currentEditorIsActive, tab.webView.url?.scheme != "glass" { view.window?.makeFirstResponder(tab.webView) }
        updateChrome()
        notifyStateChanged()
    }

    private func observe(_ tab: BrowserTab) {
        observations = [
            tab.webView.observe(\.title, options: [.new]) { [weak self, weak tab] _, _ in DispatchQueue.main.async { self?.updateTitle(for: tab) } },
            tab.webView.observe(\.url, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateChrome() } },
            tab.webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateChrome() } },
            tab.webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateChrome() } },
            tab.webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateChrome() } },
            tab.webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in DispatchQueue.main.async { self?.updateChrome() } }
        ]
    }

    private func updateTitle(for tab: BrowserTab?) {
        guard let tab else { return }
        tab.title = tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled"
        rebuildTabControl()
        if tab === tabs[selectedIndex] { view.window?.title = privateMode ? "\(tab.title) — Private — AINCRAD Browser" : "\(tab.title) — AINCRAD Browser" }
        notifyStateChanged()
    }

    private func rebuildTabControl() {
        guard isViewLoaded else { return }
        tabControl.segmentCount = tabs.count
        for (index, tab) in tabs.enumerated() {
            let prefix = tab.pinned ? "◆ " : ""
            tabControl.setLabel(prefix + String(tab.title.prefix(28)), forSegment: index)
            tabControl.setWidth(max(110, min(220, CGFloat(tab.title.count * 7 + 44))), forSegment: index)
            tabControl.setToolTip(tab.title, forSegment: index)
            tabControl.setImage(tab.icon, forSegment: index)
        }
        if tabs.indices.contains(selectedIndex) { tabControl.selectedSegment = selectedIndex }
    }

    private func updateChrome() {
        guard tabs.indices.contains(selectedIndex) else { return }
        let web = tabs[selectedIndex].webView
        backButton.isEnabled = web.canGoBack; forwardButton.isEnabled = web.canGoForward
        reloadButton.image = NSImage(systemSymbolName: web.isLoading ? "xmark" : "arrow.clockwise", accessibilityDescription: web.isLoading ? "Stop" : "Reload")
        let value = web.estimatedProgress
        progress.doubleValue = value; progress.isHidden = !web.isLoading || value >= 1
        if !addressField.currentEditorIsActive { addressField.stringValue = web.url?.scheme == "glass" ? "" : (web.url?.absoluteString ?? "") }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { navigate(addressField.stringValue); return true }
        return false
    }

    private func navigate(_ input: String) {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let url: URL?
        if let explicit = URL(string: raw), explicit.scheme != nil { url = explicit }
        else if raw.contains(".") && !raw.contains(" ") { url = URL(string: "https://\(raw)") }
        else {
            let query = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
            url = URL(string: String(format: BrowserStore.shared.searchTemplate, query))
        }
        if let url { openURL(url) }
    }

    func openURL(_ url: URL) { tabs[selectedIndex].webView.load(URLRequest(url: url)) }
    func focusAddressBar() { view.window?.makeFirstResponder(addressField); addressField.selectText(nil) }
    @objc private func goBack() { tabs[selectedIndex].webView.goBack() }
    @objc private func goForward() { tabs[selectedIndex].webView.goForward() }
    @objc private func reloadOrStop() {
        let web = tabs[selectedIndex].webView
        if web.isLoading { web.stopLoading() } else { web.reload() }
    }
    @objc private func toggleSidebarAction() { toggleSidebar() }
    @objc private func bookmarkAction() { bookmarkCurrentPage() }
    @objc private func shareAction() { sharePage() }
    @objc private func downloadsAction() { DownloadManager.shared.showWindow() }

    func toggleSidebar() {
        sidebarVisible.toggle(); sidebar.view.isHidden = !sidebarVisible
        splitView.setPosition(sidebarVisible ? 230 : 0, ofDividerAt: 0)
    }

    func showSidebar(section: SidebarSection) {
        sidebar.section = section
        if !sidebarVisible { toggleSidebar() }
    }

    func bookmarkCurrentPage() {
        guard !privateMode, let url = tabs[selectedIndex].webView.url, url.scheme != "glass" else { return }
        BrowserStore.shared.addBookmark(url: url, title: tabs[selectedIndex].title)
        let original = bookmarkButton.image
        bookmarkButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Bookmarked")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.bookmarkButton.image = original }
    }

    func showFind() {
        let alert = NSAlert(); alert.messageText = "Find on Page"; alert.addButton(withTitle: "Find"); alert.addButton(withTitle: "Cancel")
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 280, height: 26)); alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let configuration = WKFindConfiguration(); configuration.wraps = true
            tabs[selectedIndex].webView.find(field.stringValue, configuration: configuration) { _ in }
        }
    }

    func copyPageLink() {
        guard let url = tabs[selectedIndex].webView.url, url.scheme != "glass" else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL])
    }

    func sharePage() {
        guard let url = tabs[selectedIndex].webView.url, url.scheme != "glass" else { NSSound.beep(); return }
        NSSharingServicePicker(items: [url]).show(relativeTo: shareButton.bounds, of: shareButton, preferredEdge: .maxY)
    }

    func printPage() {
        tabs[selectedIndex].webView.printOperation(with: NSPrintInfo.shared).run()
    }

    func savePageAsPDF() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "\(tabs[selectedIndex].title).pdf"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        tabs[selectedIndex].webView.createPDF(configuration: WKPDFConfiguration()) { result in
            do { try result.get().write(to: destination, options: .atomic) }
            catch { DispatchQueue.main.async { NSAlert(error: error).runModal() } }
        }
    }

    func windowState() -> WindowState { WindowState(tabs: tabs.map(\.state), selectedIndex: selectedIndex) }
    private func notifyStateChanged() { NotificationCenter.default.post(name: .browserWindowStateChanged, object: nil) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let index = tabs.firstIndex(where: { $0.webView === webView }) else { return }
        let tab = tabs[index]
        if let url = webView.url, !privateMode, url.scheme != "glass", url != tab.lastCommittedURL {
            tab.lastCommittedURL = url
            BrowserStore.shared.recordVisit(url: url, title: webView.title ?? url.host ?? url.absoluteString)
        }
        updateTitle(for: tab); updateChrome()
        loadFavicon(for: tab)
    }

    @objc private func refreshStartPages() {
        for tab in tabs where tab.webView.url?.scheme == "glass" || tab.webView.url == nil {
            tab.webView.loadHTMLString(StartPage.html(privateMode: privateMode), baseURL: URL(string: "glass://start"))
        }
    }

    private func loadFavicon(for tab: BrowserTab) {
        guard let pageURL = tab.webView.url, pageURL.scheme == "https" || pageURL.scheme == "http" else { tab.icon = nil; return }
        let script = "document.querySelector('link[rel~=icon]')?.href || new URL('/favicon.ico', location.href).href"
        tab.webView.evaluateJavaScript(script) { [weak self, weak tab] value, _ in
            guard let tab, let raw = value as? String, let iconURL = URL(string: raw) else { return }
            URLSession.shared.dataTask(with: iconURL) { data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                image.size = NSSize(width: 16, height: 16)
                DispatchQueue.main.async { tab.icon = image; self?.rebuildTabControl() }
            }.resume()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showLoadError(error, in: webView) }
    private func showLoadError(_ error: Error, in webView: WKWebView) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        let escaped = error.localizedDescription.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        webView.loadHTMLString("<meta name='color-scheme' content='light dark'><style>body{font:16px -apple-system;padding:12vh 18%;}h1{font-size:30px;color:#f5a623}</style><h1>AINCRAD Browser couldn’t open this page</h1><p>\(escaped)</p>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if ["http", "https", "file", "about", "data", "blob", "glass"].contains(url.scheme?.lowercased() ?? "") { decisionHandler(.allow) }
        else { NSWorkspace.shared.open(url); decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { DownloadManager.shared.begin(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { DownloadManager.shared.begin(download) }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        createTab(state: nil, select: true)
        if let url = navigationAction.request.url { openURL(url) }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let index = tabs.firstIndex(where: { $0.webView === webView }) { selectedIndex = index; closeCurrentTab() }
    }

    @available(macOS 12.0, *)
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let host = origin.host
        let saved = BrowserStore.shared.permissions(for: host)
        let existing: SitePermission = type == .camera ? saved.camera : type == .microphone ? saved.microphone : (saved.camera == saved.microphone ? saved.camera : .ask)
        if existing != .ask { decisionHandler(existing == .allow ? .grant : .deny); return }
        let kind = type == .camera ? "camera" : type == .microphone ? "microphone" : "camera and microphone"
        let alert = NSAlert(); alert.messageText = "Allow \(host) to use your \(kind)?"; alert.informativeText = "Only allow websites you trust."; alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Don’t Allow")
        let remember = NSButton(checkboxWithTitle: "Remember for this website", target: nil, action: nil); alert.accessoryView = remember
        let allow = alert.runModal() == .alertFirstButtonReturn
        if remember.state == .on {
            var updated = saved; let choice: SitePermission = allow ? .allow : .deny
            if type == .camera { updated.camera = choice } else if type == .microphone { updated.microphone = choice } else { updated.camera = choice; updated.microphone = choice }
            BrowserStore.shared.setPermissions(updated, for: host)
        }
        decisionHandler(allow ? .grant : .deny)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private extension NSTextField {
    var currentEditorIsActive: Bool { currentEditor() != nil }
}

extension Notification.Name {
    static let browserWindowStateChanged = Notification.Name("AINCRADBrowserWindowStateChanged")
}

/// AppKit darkens a segmented control's selected colour (the pink theme came out purple),
/// so the tab strip draws its own track and selection in the exact theme colours.
final class SolidSegmentedControl: NSSegmentedControl {
    override class var cellClass: AnyClass? { get { SolidSegmentedCell.self } set {} }
    override var allowsVibrancy: Bool { false }
}

final class SolidSegmentedCell: NSSegmentedCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let height: CGFloat = 20
        var x = cellFrame.minX + 2
        let y = cellFrame.midY - height / 2
        AINCRADTheme.footer.setFill()
        let total = (0..<segmentCount).reduce(CGFloat(0)) { $0 + width(forSegment: $1) }
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: total, height: height), xRadius: 5, yRadius: 5).fill()
        for i in 0..<segmentCount {
            let rect = NSRect(x: x, y: y, width: width(forSegment: i), height: height)
            if i == selectedSegment {
                AINCRADTheme.tabBezel.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
            } else if i > 0 && i - 1 != selectedSegment {
                AINCRADTheme.panelText.withAlphaComponent(0.15).setFill()
                NSRect(x: rect.minX, y: rect.minY + 4, width: 1, height: height - 8).fill()
            }
            drawSegment(i, inFrame: rect, with: controlView)
            x += rect.width
        }
    }

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        let selected = segment == selectedSegment
        var textX = frame.minX + 8
        let label = label(forSegment: segment) ?? ""
        let attrs: [NSAttributedString.Key: Any] = [.font: font ?? .systemFont(ofSize: 13),
                                                    .foregroundColor: selected ? AINCRADTheme.accentText : AINCRADTheme.panelText]
        let size = label.size(withAttributes: attrs)
        var contentWidth = size.width
        let image = image(forSegment: segment)
        if image != nil { contentWidth += 20 }
        textX = max(textX, frame.midX - contentWidth / 2)
        if let image {
            image.draw(in: NSRect(x: textX, y: frame.midY - 7, width: 14, height: 14))
            textX += 20
        }
        let maxWidth = frame.maxX - 8 - textX
        (label as NSString).draw(with: NSRect(x: textX, y: frame.midY - size.height / 2, width: maxWidth, height: size.height),
                                 options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
    }
}
