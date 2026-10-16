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
    var progressObservation: NSKeyValueObservation?
    init(download: WKDownload, filename: String) { self.download = download; self.filename = filename }
}

final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()
    private(set) var records: [DownloadRecord] = []
    private var windowController: DownloadsWindowController?

    func begin(_ download: WKDownload) {
        if !records.contains(where: { $0.download === download }) {
            records.insert(DownloadRecord(download: download, filename: download.originalRequest?.url?.lastPathComponent.nonEmpty ?? "Download"), at: 0)
        }
        let record = recordFor(download)
        record.progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self, weak record] progress, _ in
            guard let record, !record.finished else { return }
            DispatchQueue.main.async { record.status = "\(Int(progress.fractionCompleted * 100))%"; self?.changed() }
        }
        download.delegate = self; changed()
    }

    func showWindow() {
        let controller = windowController ?? DownloadsWindowController(manager: self)
        windowController = controller; controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func cancel(_ record: DownloadRecord) {
        guard !record.finished else { return }
        record.download.cancel { _ in }
        record.status = "Cancelled"; record.failed = true; record.finished = true; changed()
    }

    func clearFinished() { records.removeAll { $0.finished }; changed() }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let record = recordFor(download); record.filename = suggestedFilename
        let panel = NSSavePanel(); panel.nameFieldStringValue = suggestedFilename; panel.canCreateDirectories = true
        panel.begin { [weak self] result in
            let destination = result == .OK ? panel.url : nil
            record.destination = destination; record.status = destination == nil ? "Cancelled" : "Downloading…"
            if destination == nil { record.finished = true }
            self?.changed(); completionHandler(destination)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let record = recordFor(download); record.status = "Finished"; record.finished = true; changed()
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

final class DownloadsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let manager: DownloadManager
    private let table = NSTableView()
    init(manager: DownloadManager) {
        self.manager = manager
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Downloads"
        super.init(window: window); window.center(); buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .downloadsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func buildUI() {
        let root = NSView(); window?.contentView = root
        let name = NSTableColumn(identifier: .init("name")); name.title = "File"; name.width = 330
        let status = NSTableColumn(identifier: .init("status")); status.title = "Status"; status.width = 180
        table.addTableColumn(name); table.addTableColumn(status); table.delegate = self; table.dataSource = self; table.rowHeight = 34; table.doubleAction = #selector(reveal); table.target = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false
        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(reveal)); let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel)); let clear = NSButton(title: "Clear Finished", target: self, action: #selector(clear))
        let actions = NSStackView(views: [reveal, cancel, clear]); actions.spacing = 8; actions.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll); root.addSubview(actions)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -10), actions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)])
    }
    func numberOfRows(in tableView: NSTableView) -> Int { manager.records.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let record = manager.records[row]; let text = tableColumn?.identifier.rawValue == "name" ? record.filename : record.status
        let field = NSTextField(labelWithString: text); field.lineBreakMode = .byTruncatingMiddle; return field
    }
    @objc private func reload() { table.reloadData() }
    private var selected: DownloadRecord? { table.selectedRow >= 0 ? manager.records[table.selectedRow] : nil }
    @objc private func reveal() { if let url = selected?.destination { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSSound.beep() } }
    @objc private func cancel() { if let selected { manager.cancel(selected) } }
    @objc private func clear() { manager.clearFinished() }
}

extension Notification.Name { static let downloadsChanged = Notification.Name("AINCRADDownloadsChanged") }
private extension String { var nonEmpty: String? { isEmpty ? nil : self } }
