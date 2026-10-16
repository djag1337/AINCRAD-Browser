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
    private let toolbar = DragToolbarView()
    /// The theme's panel colour, laid over the blur (a visual effect view draws over its own layer colour).
    private let toolbarTint = NSView()
    private let tabControl = TabStripView()
    /// https links we swapped in for http ones, so a site without https can fall back to the original.
    private var upgradedFrom: [String: URL] = [:]
    private var noUpgrade = Set<String>()
    private let addressField = NSSearchField()
    private let progress = NSProgressIndicator()
    private let backButton = CircleButton()
    private let forwardButton = CircleButton()
    private let reloadButton = CircleButton()
    private let sidebarButton = CircleButton()
    private let addTabButton = CircleButton()
    private let bookmarkButton = CircleButton()
    private let shareButton = CircleButton()
    private let downloadsButton = CircleButton()
    /// Opens the AINCRAD launcher (shown only when AINCRAD is installed).
    private let aincradButton = CircleButton()
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
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged), name: AINCRADTheme.changed, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(prefsChanged), name: .browserPrefsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rulesReady), name: .browserFeaturesReady, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        applyTheme()
        installMouseMonitor()
        // Show the bar for a moment on open so you can see where it lives, then tuck it away.
        if autoHide { scheduleHide(after: 2.0) }
    }

    deinit {
        if let moveMonitor { NSEvent.removeMonitor(moveMonitor) }
        if let globalMoveMonitor { NSEvent.removeMonitor(globalMoveMonitor) }
    }

    // MARK: Auto-hiding toolbar

    private var toolbarHeight: CGFloat { 10 + AINCRADTheme.buttonSize + 10 + 34 + 12 }
    private var toolbarHeightConstraint: NSLayoutConstraint?
    private var webTopConstraint: NSLayoutConstraint?
    private var toolbarShown = true
    private var hideWork: DispatchWorkItem?
    private var moveMonitor: Any?
    private var autoHide: Bool { BrowserPrefsModel.shared.prefs.autoHideToolbar }

    /// Keep the bar up while you're typing in the address field.
    private var keepToolbar: Bool { addressField.currentEditorIsActive }

    private var globalMoveMonitor: Any?

    private func installMouseMonitor() {
        guard moveMonitor == nil else { return }
        view.window?.acceptsMouseMovedEvents = true
        moveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.pointerMoved(); return event
        }
        // Also while another app is active, so the bar still appears when you reach for it.
        globalMoveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in self?.pointerMoved() }
    }

    private func pointerMoved() {
        guard let window = view.window, window.isVisible else { return }
        guard autoHide else { setToolbar(shown: true); return }
        let mouse = NSEvent.mouseLocation
        let frame = window.frame
        let fromTop = frame.maxY - mouse.y
        let inside = mouse.x >= frame.minX && mouse.x <= frame.maxX && fromTop >= -4
        let zone = toolbarShown ? toolbarHeight + 12 : 48
        if inside, fromTop <= zone { hideWork?.cancel(); hideWork = nil; setToolbar(shown: true) }
        else if toolbarShown, !keepToolbar { scheduleHide(after: 0.5) }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWork = nil
            if self.autoHide, !self.keepToolbar { self.setToolbar(shown: false) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func setToolbar(shown: Bool, animated: Bool = true) {
        guard shown != toolbarShown, isViewLoaded else { return }
        toolbarShown = shown
        if shown { toolbar.isHidden = false }
        let lights = view.window?.standardWindowButton(.closeButton)?.superview
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = animated ? 0.18 : 0
            context.allowsImplicitAnimation = true
            toolbar.animator().alphaValue = shown ? 1 : 0
            lights?.animator().alphaValue = shown ? 1 : 0
            webTopConstraint?.animator().constant = shown ? toolbarHeight : 8
            view.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            if let self, !self.toolbarShown { self.toolbar.isHidden = true }
        })
    }

    @objc private func prefsChanged() {
        BrowserFeatures.shared.prefsChanged()
        applyTheme()
        if !autoHide { setToolbar(shown: true) }
        tabs.forEach { BrowserFeatures.shared.configure($0) }
        refreshStartPages()
    }

    /// Content rules finished compiling (or were removed): attach them to open tabs. Doesn't re-trigger a compile.
    @objc private func rulesReady() { tabs.forEach { BrowserFeatures.shared.configure($0) } }

    func toggleReader() {
        guard tabs.indices.contains(selectedIndex), tabs[selectedIndex].webView.url?.scheme != "glass" else { NSSound.beep(); return }
        tabs[selectedIndex].webView.evaluateJavaScript(BrowserFeatures.shared.readerScript()) { _, _ in }
    }

    @objc private func themeChanged() {
        applyTheme()
        refreshStartPages()
    }

    /// Repaints the chrome in AINCRAD's current theme (called on launch and whenever it changes).
    private func applyTheme() {
        let dark = AINCRADTheme.isDark
        view.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        // Dark themes' panels are see-through, which the blur turns grey; keep them solid.
        // Floating (default): the bar is see-through and only the buttons, address bar and tabs have a surface.
        for button in [sidebarButton, backButton, forwardButton, reloadButton, bookmarkButton, shareButton, downloadsButton, addTabButton, aincradButton] {
            button.constraints.forEach { $0.constant = AINCRADTheme.buttonSize }
        }
        addressField.constraints.first { $0.firstAttribute == .height }?.constant = AINCRADTheme.buttonSize
        addressField.layer?.cornerRadius = AINCRADTheme.buttonSize / 2
        toolbarHeightConstraint?.constant = toolbarHeight
        if toolbarShown { webTopConstraint?.constant = toolbarHeight }
        let floating = BrowserPrefsModel.shared.prefs.floatingToolbar
        toolbarTint.layer?.backgroundColor = floating ? NSColor.clear.cgColor : (dark ? AINCRADTheme.panel.withAlphaComponent(1) : AINCRADTheme.panel).cgColor
        webContainer.layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.055, green: 0.063, blue: 0.086, alpha: 1) : NSColor.white).cgColor
        webContainer.layer?.borderColor = AINCRADTheme.accent.withAlphaComponent(0.55).cgColor
        webContainer.layer?.cornerRadius = floating ? 10 : 0
        webContainer.layer?.borderWidth = floating ? 1.2 : 0
        addressField.layer?.backgroundColor = AINCRADTheme.circle.withAlphaComponent(1).cgColor
        for button in [sidebarButton, backButton, forwardButton, reloadButton, bookmarkButton, shareButton, downloadsButton, addTabButton, aincradButton] {
            button.restyle()
        }
        aincradButton.image = AINCRADTheme.makeMark(size: 18)
        addressField.layer?.borderColor = AINCRADTheme.accent.cgColor
        addressField.font = AINCRADTheme.bodyFont(size: max(15, AINCRADTheme.bodySize * 0.8))
        tabControl.applyTheme()
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
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        mainView.addSubview(toolbar)
        toolbar.wantsLayer = true
        toolbarTint.wantsLayer = true
        toolbarTint.frame = toolbar.bounds
        toolbarTint.autoresizingMask = [.width, .height]
        toolbar.addSubview(toolbarTint)

        func symbolButton(_ button: CircleButton, symbol: String, action: Selector, help: String) {
            button.image = AINCRADTheme.glyph(symbol, help)
            button.bezelStyle = .texturedRounded; button.isBordered = false
            button.target = self; button.action = action; button.toolTip = help
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: AINCRADTheme.buttonSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: AINCRADTheme.buttonSize).isActive = true
            button.imagePosition = .imageOnly
            (button as? CircleButton)?.restyle()
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
        addressField.layer?.cornerRadius = AINCRADTheme.buttonSize / 2
        addressField.layer?.borderWidth = 1.5
        addressField.layer?.borderColor = AINCRADTheme.accent.cgColor
        addressField.layer?.backgroundColor = AINCRADTheme.circle.withAlphaComponent(1).cgColor
        addressField.font = AINCRADTheme.bodyFont(size: max(15, AINCRADTheme.bodySize * 0.8))

        tabControl.onSelect = { [weak self] in self?.selectTab(at: $0) }
        tabControl.onClose = { [weak self] in self?.closeTab(at: $0) }
        tabControl.menuFor = { [weak self] in self?.tabMenu(for: $0) }
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        progress.style = .bar; progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1
        progress.translatesAutoresizingMaskIntoConstraints = false; progress.isHidden = true

        privacyBadge.font = .systemFont(ofSize: 9, weight: .bold)
        privacyBadge.textColor = AINCRADTheme.accent
        privacyBadge.isHidden = !privateMode
        privacyBadge.translatesAutoresizingMaskIntoConstraints = false

        productLabel.font = AINCRADTheme.displayFont(size: 11)
        productLabel.textColor = AINCRADTheme.panelText

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
        [nav, addressField, right, tabControl, addTabButton, progress].forEach(toolbar.addSubview)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: mainView.topAnchor), toolbar.leadingAnchor.constraint(equalTo: mainView.leadingAnchor), toolbar.trailingAnchor.constraint(equalTo: mainView.trailingAnchor), toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            nav.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 76), nav.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10),
            addressField.leadingAnchor.constraint(equalTo: nav.trailingAnchor, constant: 8), addressField.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 10), addressField.heightAnchor.constraint(equalToConstant: AINCRADTheme.buttonSize),
            right.leadingAnchor.constraint(equalTo: addressField.trailingAnchor, constant: 8), right.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12), right.centerYAnchor.constraint(equalTo: addressField.centerYAnchor),
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
            tabControl.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14), tabControl.trailingAnchor.constraint(equalTo: addTabButton.leadingAnchor, constant: -6), tabControl.topAnchor.constraint(equalTo: addressField.bottomAnchor, constant: 11), tabControl.heightAnchor.constraint(equalToConstant: 34),
            addTabButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10), addTabButton.centerYAnchor.constraint(equalTo: tabControl.centerYAnchor),
            progress.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor), progress.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor), progress.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor), progress.heightAnchor.constraint(equalToConstant: 2)
        ])
        toolbarHeightConstraint = toolbar.constraints.first { $0.firstAttribute == .height && $0.secondItem == nil }
        rebuildTabControl()
    }

    private func configureWebContainer() {
        webTopConstraint = webContainer.topAnchor.constraint(equalTo: mainView.topAnchor, constant: toolbarHeight)
        webContainer.translatesAutoresizingMaskIntoConstraints = false
        webContainer.wantsLayer = true
        webContainer.layer?.masksToBounds = true
        mainView.addSubview(webContainer)
        NSLayoutConstraint.activate([
            webTopConstraint!, webContainer.leadingAnchor.constraint(equalTo: mainView.leadingAnchor, constant: 8), webContainer.trailingAnchor.constraint(equalTo: mainView.trailingAnchor, constant: -8), webContainer.bottomAnchor.constraint(equalTo: mainView.bottomAnchor, constant: -8)
        ])
    }

    private func createTab(state: TabState?, select: Bool, blank: Bool = false) {
        let tab = BrowserTab(privateMode: privateMode)
        tab.webView.navigationDelegate = self; tab.webView.uiDelegate = self
        tab.pinned = state?.pinned ?? false
        tabs.append(tab)
        if let state, let url = URL(string: state.url), url.scheme != "glass" {
            tab.webView.load(URLRequest(url: url)); tab.title = state.title
        } else if blank {
            tab.webView.loadHTMLString(StartPage.blank(), baseURL: URL(string: "glass://start"))
        } else {
            tab.webView.loadHTMLString(StartPage.html(privateMode: privateMode), baseURL: URL(string: "glass://start"))
        }
        if isViewLoaded { rebuildTabControl() }
        if select { selectTab(at: tabs.count - 1) }
    }

    func newTab() { createTab(state: nil, select: true, blank: BrowserPrefsModel.shared.prefs.newTabPage == "blank"); focusAddressBar() }
    @objc private func addTabAction() { newTab() }

    var currentIndex: Int { selectedIndex }
    func closeCurrentTab() { closeTab(at: selectedIndex) }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.count == 1 { view.window?.performClose(nil); return }
        let removed = tabs.remove(at: index)
        removed.webView.stopLoading()
        if !privateMode, removed.webView.url?.scheme != "glass" { BrowserStore.shared.rememberClosed(removed.state) }
        if index < selectedIndex { selectedIndex -= 1 } else if index == selectedIndex { selectedIndex = min(selectedIndex, tabs.count - 1) }
        rebuildTabControl(); selectTab(at: selectedIndex); notifyStateChanged()
    }

    func closeOtherTabs(keeping index: Int) {
        guard tabs.indices.contains(index) else { return }
        let keep = tabs[index]
        for tab in tabs where tab !== keep && !tab.pinned {
            tab.webView.stopLoading()
            if !privateMode, tab.webView.url?.scheme != "glass" { BrowserStore.shared.rememberClosed(tab.state) }
        }
        tabs = tabs.filter { $0 === keep || $0.pinned }
        selectedIndex = tabs.firstIndex { $0 === keep } ?? 0
        rebuildTabControl(); selectTab(at: selectedIndex); notifyStateChanged()
    }

    func closeTabsToRight(of index: Int) {
        guard tabs.indices.contains(index), index < tabs.count - 1 else { return }
        for tab in tabs[(index + 1)...] where !tab.pinned {
            tab.webView.stopLoading()
            if !privateMode, tab.webView.url?.scheme != "glass" { BrowserStore.shared.rememberClosed(tab.state) }
        }
        tabs = Array(tabs[...index]) + tabs[(index + 1)...].filter(\.pinned)
        selectedIndex = min(selectedIndex, tabs.count - 1)
        rebuildTabControl(); selectTab(at: selectedIndex); notifyStateChanged()
    }

    private func tabMenu(for index: Int) -> NSMenu? {
        guard tabs.indices.contains(index) else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(runMenuAction(_:)), keyEquivalent: ""); item.target = self
            item.representedObject = action; menu.addItem(item)
        }
        add("Close Tab") { [weak self] in self?.closeTab(at: index) }
        if tabs.count > 1 { add("Close Other Tabs") { [weak self] in self?.closeOtherTabs(keeping: index) } }
        if index < tabs.count - 1 { add("Close Tabs to the Right") { [weak self] in self?.closeTabsToRight(of: index) } }
        menu.addItem(.separator())
        add(tabs[index].pinned ? "Unpin Tab" : "Pin Tab") { [weak self] in self?.togglePin(at: index) }
        add("Duplicate Tab") { [weak self] in
            guard let self, self.tabs.indices.contains(index) else { return }
            self.createTab(state: self.tabs[index].state, select: true)
        }
        add("Reload Tab") { [weak self] in self?.tabs[safe: index]?.webView.reload() }
        return menu
    }

    @objc private func runMenuAction(_ sender: NSMenuItem) { (sender.representedObject as? () -> Void)?() }

    private func togglePin(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].pinned.toggle()
        // Pinned tabs sit together at the left.
        let current = tabs[selectedIndex]
        tabs = tabs.filter(\.pinned) + tabs.filter { !$0.pinned }
        selectedIndex = tabs.firstIndex { $0 === current } ?? 0
        rebuildTabControl(); notifyStateChanged()
    }

    // MARK: Keyboard-driven navigation

    func nextTab(by delta: Int) {
        guard tabs.count > 1 else { return }
        selectTab(at: (selectedIndex + delta + tabs.count) % tabs.count)
    }

    /// ⌘1…⌘8 pick that tab; ⌘9 picks the last one.
    func selectTabNumber(_ number: Int) {
        guard !tabs.isEmpty else { return }
        selectTab(at: number >= 9 ? tabs.count - 1 : min(number - 1, tabs.count - 1))
    }

    func goBackAction() { if tabs[selectedIndex].webView.canGoBack { tabs[selectedIndex].webView.goBack() } }
    func goForwardAction() { if tabs[selectedIndex].webView.canGoForward { tabs[selectedIndex].webView.goForward() } }
    func reloadAction(hard: Bool) { hard ? tabs[selectedIndex].webView.reloadFromOrigin() : tabs[selectedIndex].webView.reload() }
    func stopAction() { tabs[selectedIndex].webView.stopLoading() }

    func reopenClosedTab() {
        guard !privateMode, let state = BrowserStore.shared.popClosed() else { return }
        createTab(state: state, select: true)
    }

    func duplicateCurrentTab() {
        guard tabs.indices.contains(selectedIndex) else { return }
        createTab(state: tabs[selectedIndex].state, select: true)
    }

    func togglePinCurrentTab() { togglePin(at: selectedIndex) }

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
        tabControl.select(index)
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
        tab.title = tab.webView.url?.scheme == "glass" || tab.webView.url == nil
            ? "New Tab" : (tab.webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? tab.webView.url?.host ?? "Untitled")
        rebuildTabControl()
        if tab === tabs[selectedIndex] { view.window?.title = privateMode ? "\(tab.title) — Private — AINCRAD Browser" : "\(tab.title) — AINCRAD Browser" }
        notifyStateChanged()
    }

    private func rebuildTabControl() {
        guard isViewLoaded else { return }
        tabControl.reload(tabs.map { .init(title: $0.title, icon: $0.icon, pinned: $0.pinned) }, selected: selectedIndex)
    }

    private func updateChrome() {
        guard tabs.indices.contains(selectedIndex) else { return }
        let web = tabs[selectedIndex].webView
        backButton.isEnabled = web.canGoBack; forwardButton.isEnabled = web.canGoForward
        reloadButton.image = AINCRADTheme.glyph(web.isLoading ? "xmark" : "arrow.clockwise", web.isLoading ? "Stop" : "Reload")
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
            url = BrowserPrefsModel.shared.prefs.searchURL(for: raw)
        }
        if let url { openURL(url) }
    }

    func openURL(_ url: URL) { tabs[selectedIndex].webView.load(URLRequest(url: url)) }
    func focusAddressBar() { setToolbar(shown: true); view.window?.makeFirstResponder(addressField); addressField.selectText(nil) }
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

    private var lastFind = ""
    func findAgain(backwards: Bool) {
        guard !lastFind.isEmpty else { showFind(); return }
        let configuration = WKFindConfiguration(); configuration.wraps = true; configuration.backwards = backwards
        tabs[selectedIndex].webView.find(lastFind, configuration: configuration) { _ in }
    }

    func showFind() {
        let alert = NSAlert(); alert.messageText = "Find on Page"; alert.addButton(withTitle: "Find"); alert.addButton(withTitle: "Cancel")
        let field = NSSearchField(frame: NSRect(x: 0, y: 0, width: 280, height: 26)); alert.accessoryView = field
        field.stringValue = lastFind
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            lastFind = field.stringValue
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
        // An https upgrade the site can't serve falls back to the original http link.
        if let failing = (error as NSError).userInfo[NSURLErrorFailingURLStringErrorKey] as? String, let original = upgradedFrom.removeValue(forKey: failing) {
            var request = URLRequest(url: original); request.setValue("1", forHTTPHeaderField: "X-AINCRAD-No-Upgrade")
            noUpgrade.insert(original.absoluteString); webView.load(request); return
        }
        let escaped = error.localizedDescription.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        webView.loadHTMLString("<meta name='color-scheme' content='light dark'><style>body{font:16px -apple-system;padding:12vh 18%;}h1{font-size:30px;color:#f5a623}</style><h1>AINCRAD Browser couldn’t open this page</h1><p>\(escaped)</p>", baseURL: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.shouldPerformDownload { decisionHandler(.download); return }
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame ?? true, ["http", "https"].contains(url.scheme ?? "") {
            if let clean = BrowserFeatures.shared.cleaned(url) { decisionHandler(.cancel); webView.load(URLRequest(url: clean)); return }
            if !noUpgrade.contains(url.absoluteString), let secure = BrowserFeatures.shared.upgraded(url) {
                upgradedFrom[secure.absoluteString] = url
                decisionHandler(.cancel); webView.load(URLRequest(url: secure)); return
            }
        }
        if ["http", "https", "file", "about", "data", "blob", "glass"].contains(url.scheme?.lowercased() ?? "") { decisionHandler(.allow) }
        else { NSWorkspace.shared.open(url); decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { DownloadManager.shared.begin(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { DownloadManager.shared.begin(download) }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if BrowserPrefsModel.shared.prefs.blockPopups, navigationAction.navigationType == .other, !BrowserFeatures.shared.userJustActed { return nil }
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

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// The see-through bar above the page: dragging its empty space moves the window, double-click zooms it.
final class DragToolbarView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { super.mouseDown(with: event) }
    }
}
