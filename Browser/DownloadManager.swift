import AppKit
@preconcurrency import WebKit

final class DownloadRecord: NSObject {
    let id = UUID()
    let download: WKDownload
    var filename: String
    var destination: URL?
    var status = "Preparing…"
    var finished = false
    var failed = false
    var fraction = 0.0
    var received: Int64 = 0
    var total: Int64 = 0
    let started = Date()
    var progressObservation: NSKeyValueObservation?
    init(download: WKDownload, filename: String) { self.download = download; self.filename = filename }
}

final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private(set) var records: [DownloadRecord] = []

    func begin(_ download: WKDownload) {
        if !records.contains(where: { $0.download === download }) {
            records.insert(DownloadRecord(download: download, filename: download.originalRequest?.url?.lastPathComponent.nonEmpty ?? "Download"), at: 0)
        }
        let record = recordFor(download)
        record.progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self, weak record] progress, _ in
            guard let record, !record.finished else { return }
            DispatchQueue.main.async {
                guard !record.finished else { return }
                record.fraction = progress.fractionCompleted
                record.received = progress.completedUnitCount; record.total = progress.totalUnitCount
                record.status = DownloadManager.progressText(record)
                self?.changed()
            }
        }
        download.delegate = self; changed()
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
    }

    /// Average progress of downloads still running (nil when none are), for the ring around the button.
    var activeFraction: Double? {
        let running = records.filter { !$0.finished }
        return running.isEmpty ? nil : running.map(\.fraction).reduce(0, +) / Double(running.count)
    }
    /// Finished since the list was last opened: the button shows a dot.
    var hasUnseen = false

    static let bytes: ByteCountFormatter = { let f = ByteCountFormatter(); f.countStyle = .file; return f }()

    /// Safari-style: "1.2 MB of 5 MB — 3 seconds left".
    static func progressText(_ r: DownloadRecord) -> String {
        guard r.total > 0 else { return r.received > 0 ? bytes.string(fromByteCount: r.received) : "Starting…" }
        var text = "\(bytes.string(fromByteCount: r.received)) of \(bytes.string(fromByteCount: r.total))"
        let elapsed = Date().timeIntervalSince(r.started)
        if r.received > 0, elapsed > 1 {
            let left = Double(r.total - r.received) / (Double(r.received) / elapsed)
            text += left < 60 ? " — \(Int(left.rounded())) sec left" : " — \(Int((left / 60).rounded())) min left"
        }
        return text
    }

    func remove(_ record: DownloadRecord) {
        if !record.finished { cancel(record) }
        records.removeAll { $0 === record }; changed()
    }

    func cancel(_ record: DownloadRecord) {
        guard !record.finished else { return }
        record.download.cancel { _ in }
        record.status = "Cancelled"; record.failed = true; record.finished = true; changed()
    }

    func clearFinished() { records.removeAll { $0.finished }; changed() }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let record = recordFor(download)
        let name = (suggestedFilename as NSString).lastPathComponent.nonEmpty ?? "Download"
        record.filename = name
        if !BrowserPrefsModel.shared.prefs.askDownloadLocation, let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            let destination = Self.uniqueURL(in: folder, name: name)
            record.destination = destination; record.filename = destination.lastPathComponent; record.status = "Downloading…"
            changed(); completionHandler(destination)
            return
        }
        let panel = NSSavePanel(); panel.nameFieldStringValue = name; panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            let destination = result == .OK ? panel.url : nil
            record.destination = destination; record.status = destination == nil ? "Cancelled" : "Downloading…"
            if destination == nil { record.finished = true }
            self?.changed(); completionHandler(destination)
        }
    }

    /// "name.ext", or "name 2.ext", "name 3.ext"… if that already exists.
    private static func uniqueURL(in folder: URL, name: String) -> URL {
        var url = folder.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"); n += 1
        }
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        let record = recordFor(download); record.fraction = 1; record.finished = true; hasUnseen = true
        let size = record.destination.flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.map { Int64($0) } ?? record.total
        record.status = size > 0 ? DownloadManager.bytes.string(fromByteCount: size) : "Finished"
        changed()
        // Private windows' downloads stay private: AINCRAD isn't told about them.
        if download.webView?.configuration.websiteDataStore.isPersistent != false {
            AINCRADLink.downloadFinished(name: record.filename, path: record.destination?.path)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let record = recordFor(download); record.status = error.localizedDescription; record.failed = true; record.finished = true; changed()
    }

    private func recordFor(_ download: WKDownload) -> DownloadRecord {
        if let record = records.first(where: { $0.download === download }) { return record }
        let record = DownloadRecord(download: download, filename: download.originalRequest?.url?.lastPathComponent.nonEmpty ?? "Download")
        records.insert(record, at: 0); return record
    }
    private func changed() { NotificationCenter.default.post(name: .downloadsChanged, object: nil) }
}

/// The dropdown from the downloads button, laid out like Safari's: newest first, a row per file with its icon, name and
/// progress or size; click a finished row to open it, the magnifier to show it in Finder, ✕ to cancel or remove.
final class DownloadsListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = FirstClickTableView()
    private let empty = NSTextField(labelWithString: "No downloads")
    private let manager = DownloadManager.shared
    /// Rows live as long as their download, so their buttons keep a target (rebuilding them on every progress tick broke the buttons).
    private var rows: [UUID: DownloadRowView] = [:]
    private var shownIDs: [UUID] = []

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 340))
        let column = NSTableColumn(identifier: .init("d")); column.width = 384
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 56
        table.backgroundColor = .clear; table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.delegate = self; table.dataSource = self
        table.target = self; table.action = #selector(rowClicked)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let title = NSTextField(labelWithString: "Downloads"); title.font = AINCRADTheme.displayFont(size: 13); title.textColor = AINCRADTheme.panelText
        let clear = FirstClickButton(title: "Clear", target: self, action: #selector(clearFinished)); clear.bezelStyle = .rounded; clear.controlSize = .small
        let header = NSStackView(views: [title, NSView(), clear])
        let folder = FirstClickButton(title: "Open Downloads Folder", target: self, action: #selector(openFolder)); folder.isBordered = false
        folder.contentTintColor = AINCRADTheme.accent
        empty.alignment = .center; empty.textColor = .secondaryLabelColor
        [header, scroll, folder, empty].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14), header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: folder.topAnchor, constant: -6),
            folder.centerXAnchor.constraint(equalTo: root.centerXAnchor), folder.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor), empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        preferredContentSize = NSSize(width: 400, height: 340)
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: .downloadsChanged, object: nil)
        changed()
    }

    @objc private func changed() {
        let ids = manager.records.map(\.id)
        rows = rows.filter { ids.contains($0.key) }
        if ids != shownIDs { shownIDs = ids; table.reloadData() }
        else { rows.values.forEach { $0.update() } }   // progress ticks just refresh the existing rows
        empty.isHidden = !ids.isEmpty
    }
    /// Clicking a finished row opens its file, as in Safari.
    @objc private func rowClicked() {
        let row = table.clickedRow
        guard manager.records.indices.contains(row) else { return }
        rows[manager.records[row].id]?.openFile()
    }
    @objc private func clearFinished() { manager.clearFinished() }
    @objc private func openFolder() { if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) } }

    func numberOfRows(in tableView: NSTableView) -> Int { manager.records.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = manager.records[row]
        let view = rows[record.id] ?? DownloadRowView(record: record, manager: manager)
        rows[record.id] = view
        view.update()
        return view
    }
}

final class DownloadRowView: NSView {
    private let record: DownloadRecord
    private let manager: DownloadManager
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let revealButton = FirstClickButton()
    private let stopButton = FirstClickButton()
    private var hovering = false { didSet { layer?.backgroundColor = (hovering ? AINCRADTheme.hover : .clear).cgColor } }

    init(record: DownloadRecord, manager: DownloadManager) {
        self.record = record; self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: 384, height: 56))
        wantsLayer = true
        layer?.cornerRadius = 6
        name.font = AINCRADTheme.bodyFont(size: 15, weight: .semibold); name.textColor = AINCRADTheme.panelText; name.lineBreakMode = .byTruncatingMiddle
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        bar.style = .bar; bar.controlSize = .small; bar.minValue = 0; bar.maxValue = 1
        icon.imageScaling = .scaleProportionallyUpOrDown
        for (b, symbol, tip, action) in [(revealButton, "magnifyingglass.circle.fill", "Show in Finder", #selector(reveal)),
                                         (stopButton, "xmark.circle.fill", "", #selector(removeOrCancel))] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
            b.isBordered = false; b.toolTip = tip; b.target = self; b.action = action
        }
        let text = NSStackView(views: [name, bar, status]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 3
        [icon, text, revealButton, stopButton].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36), icon.heightAnchor.constraint(equalToConstant: 36),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(equalTo: revealButton.leadingAnchor, constant: -8),
            bar.widthAnchor.constraint(equalTo: text.widthAnchor),
            stopButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            revealButton.trailingAnchor.constraint(equalTo: stopButton.leadingAnchor, constant: -4), revealButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        update()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update() {
        name.stringValue = record.filename
        status.stringValue = record.status
        status.textColor = record.failed ? .systemRed : .secondaryLabelColor
        bar.isHidden = record.finished
        bar.isIndeterminate = record.fraction <= 0
        if bar.isIndeterminate { bar.startAnimation(nil) } else { bar.stopAnimation(nil); bar.doubleValue = record.fraction }
        let exists = record.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        icon.image = exists ? NSWorkspace.shared.icon(forFile: record.destination!.path)
            : NSWorkspace.shared.icon(for: .init(filenameExtension: (record.filename as NSString).pathExtension) ?? .data)
        revealButton.isHidden = !exists
        revealButton.contentTintColor = AINCRADTheme.accent
        stopButton.toolTip = record.finished ? "Remove from list" : "Stop download"
        stopButton.contentTintColor = .tertiaryLabelColor
        toolTip = record.finished && !record.failed ? "Click to open" : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    @objc func openFile() {
        guard record.finished, !record.failed, let url = record.destination, FileManager.default.fileExists(atPath: url.path) else { NSSound.beep(); return }
        NSWorkspace.shared.open(url)
    }
    @objc private func reveal() {
        guard let url = record.destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc private func removeOrCancel() { manager.remove(record) }
}

/// The dropdown isn't the key window, so ordinary buttons there swallow the first click; these act on it.
final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class FirstClickTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension Notification.Name {
    static let downloadsChanged = Notification.Name("AINCRADDownloadsChanged")
    static let downloadStarted = Notification.Name("AINCRADDownloadStarted")
}
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
