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
            DispatchQueue.main.async { guard !record.finished else { return }; record.fraction = progress.fractionCompleted; record.status = "\(Int(progress.fractionCompleted * 100))%"; self?.changed() }
        }
        download.delegate = self; changed()
        NotificationCenter.default.post(name: .downloadStarted, object: nil)
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
            record.destination = destination; record.status = "Downloading…"
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
        let record = recordFor(download); record.status = "Finished"; record.fraction = 1; record.finished = true; changed()
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

/// The dropdown from the downloads button: one row per download with progress, and buttons to open it, show it in Finder, cancel or remove.
final class DownloadsListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No downloads yet")
    private let manager = DownloadManager.shared

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 360))
        let column = NSTableColumn(identifier: .init("d")); column.width = 400
        table.addTableColumn(column); table.headerView = nil; table.rowHeight = 62
        table.backgroundColor = .clear; table.selectionHighlightStyle = .none
        table.intercellSpacing = NSSize(width: 0, height: 4)
        table.delegate = self; table.dataSource = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let clear = NSButton(title: "Clear Finished", target: self, action: #selector(clearFinished)); clear.bezelStyle = .rounded
        let folder = NSButton(title: "Open Downloads Folder", target: self, action: #selector(openFolder)); folder.bezelStyle = .rounded
        let bar = NSStackView(views: [folder, NSView(), clear]); bar.translatesAutoresizingMaskIntoConstraints = false
        empty.alignment = .center; empty.translatesAutoresizingMaskIntoConstraints = false; empty.textColor = .secondaryLabelColor
        [scroll, bar, empty].forEach(root.addSubview)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: root.topAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -8),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12), bar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor), empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        view = root
        preferredContentSize = NSSize(width: 420, height: 360)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .downloadsChanged, object: nil)
        reload()
    }

    @objc private func reload() { table.reloadData(); empty.isHidden = !manager.records.isEmpty }
    @objc private func clearFinished() { manager.clearFinished() }
    @objc private func openFolder() { if let url = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url) } }

    func numberOfRows(in tableView: NSTableView) -> Int { manager.records.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { DownloadRowView(record: manager.records[row], manager: manager) }
}

private final class DownloadRowView: NSView {
    private let record: DownloadRecord
    private let manager: DownloadManager

    init(record: DownloadRecord, manager: DownloadManager) {
        self.record = record; self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 58))
        wantsLayer = true
        layer?.cornerRadius = AINCRADTheme.cornerRadius
        layer?.backgroundColor = AINCRADTheme.panel.withAlphaComponent(1).cgColor
        layer?.borderColor = AINCRADTheme.panelBorder.cgColor; layer?.borderWidth = 1

        let canOpen = record.finished && !record.failed && record.destination.map { FileManager.default.fileExists(atPath: $0.path) } == true
        let icon = NSImageView(image: record.destination.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)!)
        let name = NSTextField(labelWithString: record.filename)
        name.font = AINCRADTheme.bodyFont(size: 16, weight: .semibold); name.textColor = AINCRADTheme.panelText; name.lineBreakMode = .byTruncatingMiddle
        let status = NSTextField(labelWithString: record.status)
        status.font = AINCRADTheme.bodyFont(size: 13); status.textColor = record.failed ? .systemRed : AINCRADTheme.panelText.withAlphaComponent(0.7)
        let text = NSStackView(views: [name, status]); text.orientation = .vertical; text.alignment = .leading; text.spacing = 2
        if !record.finished {
            let bar = NSProgressIndicator(); bar.isIndeterminate = record.fraction <= 0; bar.minValue = 0; bar.maxValue = 1; bar.doubleValue = record.fraction
            bar.style = .bar; bar.controlSize = .small
            if bar.isIndeterminate { bar.startAnimation(nil) }
            text.addArrangedSubview(bar); bar.widthAnchor.constraint(equalToConstant: 230).isActive = true
        }
        func button(_ symbol: String, _ tip: String, _ action: Selector, enabled: Bool = true) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!, target: self, action: action)
            b.isBordered = false; b.toolTip = tip; b.isEnabled = enabled; b.contentTintColor = enabled ? AINCRADTheme.accent : .tertiaryLabelColor
            b.widthAnchor.constraint(equalToConstant: 26).isActive = true; b.heightAnchor.constraint(equalToConstant: 26).isActive = true
            return b
        }
        let actions = NSStackView(views: [
            button("arrow.up.right.square", "Open", #selector(openFile), enabled: canOpen),
            button("magnifyingglass", "Show in Finder", #selector(reveal), enabled: record.destination != nil),
            button(record.finished ? "xmark.circle" : "stop.circle", record.finished ? "Remove from list" : "Cancel", #selector(removeOrCancel)),
        ])
        actions.spacing = 2
        icon.translatesAutoresizingMaskIntoConstraints = false
        [icon, text, actions].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; addSubview($0) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 34), icon.heightAnchor.constraint(equalToConstant: 34),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -8),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), actions.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }
    override func mouseDown(with event: NSEvent) { openFile() }   // clicking the row opens the file once it's done
    @objc private func openFile() { if record.finished, !record.failed, let url = record.destination { NSWorkspace.shared.open(url) } }
    @objc private func reveal() { if let url = record.destination { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc private func removeOrCancel() { manager.remove(record) }
}

extension Notification.Name {
    static let downloadsChanged = Notification.Name("AINCRADDownloadsChanged")
    static let downloadStarted = Notification.Name("AINCRADDownloadStarted")
}
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
