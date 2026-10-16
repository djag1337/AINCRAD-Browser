import AppKit

final class SiteSettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private let camera = NSPopUpButton()
    private let microphone = NSPopUpButton()
    private var hosts: [String] { BrowserStore.shared.sitePermissions.keys.sorted() }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Website Permissions"
        super.init(window: window); window.center(); buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .sitePermissionsChanged, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildUI() {
        let root = NSView(); window?.contentView = root
        let column = NSTableColumn(identifier: .init("host")); column.title = "Website"; table.addTableColumn(column); table.delegate = self; table.dataSource = self
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false
        let cameraLabel = NSTextField(labelWithString: "Camera:"); let micLabel = NSTextField(labelWithString: "Microphone:")
        camera.addItems(withTitles: ["Ask", "Allow", "Deny"]); microphone.addItems(withTitles: ["Ask", "Allow", "Deny"])
        camera.target = self; camera.action = #selector(permissionChanged); microphone.target = self; microphone.action = #selector(permissionChanged)
        let remove = NSButton(title: "Forget Website", target: self, action: #selector(removeSelected))
        let controls = NSStackView(views: [cameraLabel, camera, micLabel, microphone, remove]); controls.spacing = 8; controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll); root.addSubview(controls)
        NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -10), controls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { hosts.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? { NSTextField(labelWithString: hosts[row]) }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0 else { return }
        let value = BrowserStore.shared.permissions(for: hosts[table.selectedRow]); camera.selectItem(at: index(value.camera)); microphone.selectItem(at: index(value.microphone))
    }
    private func index(_ value: SitePermission) -> Int { SitePermission.allCases.firstIndex(of: value) ?? 0 }
    @objc private func permissionChanged() {
        guard table.selectedRow >= 0 else { return }
        let value = SitePermissions(camera: SitePermission.allCases[camera.indexOfSelectedItem], microphone: SitePermission.allCases[microphone.indexOfSelectedItem])
        BrowserStore.shared.setPermissions(value, for: hosts[table.selectedRow])
    }
    @objc private func removeSelected() { guard table.selectedRow >= 0 else { return }; BrowserStore.shared.clearPermissions(for: hosts[table.selectedRow]) }
    @objc private func reload() { table.reloadData() }
}

