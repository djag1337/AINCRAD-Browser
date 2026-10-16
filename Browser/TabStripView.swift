import AppKit

/// The browser's tab row, drawn like the launcher's rows: glass panels, the accent on the selected tab,
/// a close button on the selected or hovered tab, middle-click to close and a right-click menu.
final class TabStripView: NSView {
    struct Item { let title: String; let icon: NSImage?; let pinned: Bool }

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var menuFor: ((Int) -> NSMenu?)?

    private var items: [Item] = []
    private var selected = 0
    private let scroll = NSScrollView()
    private let content = NSView()
    private var views: [TabItemView] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = content
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func reload(_ items: [Item], selected: Int) {
        self.items = items
        self.selected = selected
        if views.count != items.count {
            views.forEach { $0.removeFromSuperview() }
            views = items.indices.map { index in
                let v = TabItemView()
                v.onSelect = { [weak self, weak v] in if let i = self?.views.firstIndex(where: { $0 === v }) { self?.onSelect?(i) } }
                v.onClose = { [weak self, weak v] in if let i = self?.views.firstIndex(where: { $0 === v }) { self?.onClose?(i) } }
                v.menuProvider = { [weak self, weak v] in self?.views.firstIndex(where: { $0 === v }).flatMap { self?.menuFor?($0) } }
                content.addSubview(v)
                _ = index
                return v
            }
        }
        for (i, v) in views.enumerated() { v.configure(items[i], selected: i == selected) }
        needsLayout = true
    }

    func select(_ index: Int) {
        selected = index
        for (i, v) in views.enumerated() { v.configure(items[i], selected: i == index) }
        scrollToVisible(index)
    }

    func applyTheme() { for (i, v) in views.enumerated() { v.configure(items[i], selected: i == selected) } }

    override func layout() {
        super.layout()
        guard !views.isEmpty else { return }
        let gap: CGFloat = 5
        let pinnedWidth: CGFloat = 40
        let pinnedCount = items.filter(\.pinned).count
        let normalCount = items.count - pinnedCount
        let available = bounds.width - gap * CGFloat(items.count - 1) - pinnedWidth * CGFloat(pinnedCount)
        let width = normalCount == 0 ? 0 : max(96, min(220, available / CGFloat(normalCount)))
        var x: CGFloat = 0
        for (i, v) in views.enumerated() {
            let w = items[i].pinned ? pinnedWidth : width
            v.frame = NSRect(x: x, y: 0, width: w, height: bounds.height)
            x += w + gap
        }
        content.frame = NSRect(x: 0, y: 0, width: max(bounds.width, x - gap), height: bounds.height)
        scrollToVisible(selected)
    }

    private func scrollToVisible(_ index: Int) {
        guard views.indices.contains(index) else { return }
        content.scrollToVisible(views[index].frame.insetBy(dx: -12, dy: 0))
    }
}

private final class TabItemView: NSView {
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var menuProvider: (() -> NSMenu?)?

    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let close = NSButton()
    private var hovering = false { didSet { refresh() } }
    private var isSelected = false
    private var pinned = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.cell?.isScrollable = false
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        close.target = self; close.action = #selector(closeTapped)
        close.toolTip = "Close Tab (⌘W)"
        close.translatesAutoresizingMaskIntoConstraints = false
        [icon, label, close].forEach(addSubview)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 7), label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6), close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 18), close.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ item: TabStripView.Item, selected: Bool) {
        isSelected = selected
        pinned = item.pinned
        label.stringValue = item.title
        label.isHidden = item.pinned
        icon.image = item.icon ?? NSImage(systemSymbolName: item.pinned ? "pin.fill" : "globe", accessibilityDescription: nil)
        icon.contentTintColor = item.icon == nil ? (selected ? AINCRADTheme.accentText : AINCRADTheme.panelText.withAlphaComponent(0.7)) : nil
        toolTip = item.title
        refresh()
    }

    private func refresh() {
        let t = AINCRADTheme.self
        label.font = t.bodyFont(size: 13, weight: .semibold)
        label.textColor = isSelected ? t.accentText : t.panelText
        close.contentTintColor = isSelected ? t.accentText : t.panelText
        close.isHidden = pinned || !(isSelected || hovering)
        layer?.backgroundColor = (isSelected ? t.accent : (hovering ? t.hover : t.circle)).cgColor
        layer?.borderColor = (isSelected || hovering ? t.accent : t.accent.withAlphaComponent(0.3)).cgColor
        layer?.shadowColor = t.accent.cgColor
        layer?.shadowOpacity = isSelected || hovering ? 0.45 : 0
        layer?.shadowRadius = 6
        layer?.shadowOffset = .zero
        layer?.masksToBounds = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose?() } }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    @objc private func closeTapped() { onClose?() }
}

/// A launcher-style round button: a glass circle that lights up in the accent colour under the pointer.
final class CircleButton: NSButton {
    private var hovering = false { didSet { restyle() } }

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }

    func restyle() {
        let t = AINCRADTheme.self
        isBordered = false
        wantsLayer = true
        contentTintColor = t.panelText
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.backgroundColor = (hovering ? t.hover : t.circle).cgColor
        layer?.borderWidth = 1.2
        layer?.borderColor = (hovering ? t.accent : t.accent.withAlphaComponent(0.4)).cgColor
        layer?.shadowColor = t.accent.cgColor
        layer?.shadowOpacity = hovering ? 0.55 : 0
        layer?.shadowRadius = 7
        layer?.shadowOffset = .zero
    }

    override func layout() { super.layout(); restyle() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}
