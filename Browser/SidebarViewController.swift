import AppKit

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let header = NSTextField(labelWithString: "Bookmarks")
    private let search = NSSearchField()
    private let removeButton = NSButton()
    private let clearButton = NSButton()
    var section: SidebarSection = .bookmarks { didSet { reload() } }
    var openURL: ((URL) -> Void)?

    func applyTheme() {
        guard isViewLoaded else { return }
        header.font = AINCRADTheme.displayFont(size: 17)
        header.textColor = AINCRADTheme.panelText
        view.wantsLayer = true
        view.layer?.backgroundColor = AINCRADTheme.panel.withAlphaComponent(0.6).cgColor
        table.reloadData()
    }

    override func loadView() {
        let visual = NSVisualEffectView()
        visual.material = .sidebar
        visual.blendingMode = .behindWindow
        visual.state = .active
        view = visual

        header.font = AINCRADTheme.displayFont(size: 17)
        header.textColor = AINCRADTheme.panelText
        header.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(header)
        search.placeholderString = "Search"; search.sendsSearchStringImmediately = true; search.target = self; search.action = #selector(searchChanged); search.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(search)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 38
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView()
        scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(scroll)
        removeButton.title = "Remove"; removeButton.bezelStyle = .rounded
        removeButton.target = self; removeButton.action = #selector(removeSelected)
        clearButton.title = "Clear History"; clearButton.bezelStyle = .rounded
        clearButton.target = self; clearButton.action = #selector(clearHistory)
        let actions = NSStackView(views: [removeButton, clearButton])
        actions.orientation = .horizontal; actions.spacing = 8; actions.translatesAutoresizingMaskIntoConstraints = false
        visual.addSubview(actions)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: visual.topAnchor, constant: 22),
            header.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 16),
            search.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10), search.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 12), search.trailingAnchor.constraint(equalTo: visual.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: visual.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: visual.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -8),
            actions.leadingAnchor.constraint(equalTo: visual.leadingAnchor, constant: 12), actions.bottomAnchor.constraint(equalTo: visual.bottomAnchor, constant: -12)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(reloadNotification), name: .browserDataChanged, object: nil)
    }

    @objc private func reloadNotification() { reload() }
    private func reload() {
        guard isViewLoaded else { return }
        header.stringValue = section == .bookmarks ? "Bookmarks" : "History"
        clearButton.isHidden = section == .bookmarks
        table.reloadData()
    }
    private var filteredBookmarks: [Bookmark] {
        let q = search.stringValue.lowercased(); return q.isEmpty ? BrowserStore.shared.bookmarks : BrowserStore.shared.bookmarks.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }
    private var filteredHistory: [HistoryEntry] {
        let q = search.stringValue.lowercased(); return q.isEmpty ? BrowserStore.shared.history : BrowserStore.shared.history.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }
    @objc private func searchChanged() { table.reloadData() }
    func numberOfRows(in tableView: NSTableView) -> Int { section == .bookmarks ? filteredBookmarks.count : filteredHistory.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail; label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label); cell.textField = label
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        }
        cell.textField?.stringValue = section == .bookmarks ? filteredBookmarks[row].title : filteredHistory[row].title
        return cell
    }

    @objc private func openSelected() {
        guard table.selectedRow >= 0 else { return }
        let raw = section == .bookmarks ? filteredBookmarks[table.selectedRow].url : filteredHistory[table.selectedRow].url
        if let url = URL(string: raw) { openURL?(url) }
    }

    @objc private func removeSelected() {
        let row = table.selectedRow
        guard row >= 0 else { NSSound.beep(); return }
        if section == .bookmarks { BrowserStore.shared.removeBookmark(id: filteredBookmarks[row].id) }
        else { BrowserStore.shared.removeHistory(id: filteredHistory[row].id) }
    }

    @objc private func clearHistory() {
        let alert = NSAlert(); alert.messageText = "Clear browsing history?"; alert.informativeText = "This removes AINCRAD Browser history. Website cookies and saved Apple Passwords are separate."; alert.addButton(withTitle: "Clear History"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { BrowserStore.shared.clearHistory() }
    }
}

