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

    private let fill = CAGradientLayer()
    private let shine = CALayer()
    private let badge = CALayer()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private let close = NSButton()
    private var hovering = false { didSet { refresh() } }
    private var isSelected = false
    private var pinned = false
    private var hasFavicon = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(fill)
        layer?.addSublayer(shine)
        layer?.addSublayer(badge)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        close.isBordered = false
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab")?.withSymbolConfiguration(.init(pointSize: 10, weight: .bold))
        close.target = self; close.action = #selector(closeTapped)
        close.toolTip = "Close Tab (⌘W)"
        close.translatesAutoresizingMaskIntoConstraints = false
        [icon, label, close].forEach(addSubview)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -4),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 20), close.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ item: TabStripView.Item, selected: Bool) {
        isSelected = selected
        pinned = item.pinned
        hasFavicon = item.icon != nil
        label.stringValue = item.title
        label.isHidden = item.pinned
        icon.image = item.icon ?? AINCRADTheme.glyph(item.pinned ? "pin.fill" : "globe")
        toolTip = item.title
        needsLayout = true
        refresh()
    }

    /// Rows like the launcher's: a round badge with the icon, then the title in the theme's body font.
    override func layout() {
        super.layout()
        let t = AINCRADTheme.self
        let h = bounds.height
        fill.frame = bounds
        fill.cornerRadius = t.cornerRadius
        fill.masksToBounds = true
        shine.frame = CGRect(x: t.cornerRadius, y: h - 1.5, width: max(0, bounds.width - 2 * t.cornerRadius), height: 1)
        shine.backgroundColor = NSColor.white.withAlphaComponent(t.shine).cgColor
        let b = (h * 0.72).rounded()
        let badgeFrame = CGRect(x: 7, y: ((h - b) / 2).rounded(), width: b, height: b)
        badge.frame = badgeFrame
        badge.cornerRadius = b / 2
        badge.isHidden = hasFavicon
        let inset = hasFavicon ? 0 : (b * 0.22).rounded()
        icon.frame = badgeFrame.insetBy(dx: inset, dy: inset)
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: t.cornerRadius, cornerHeight: t.cornerRadius, transform: nil)
        for c in constraints where c.firstItem === label && c.firstAttribute == .leading { removeConstraint(c) }
        label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: badgeFrame.maxX + 9).isActive = true
    }

    private func refresh() {
        let t = AINCRADTheme.self
        label.font = t.bodyFont(size: min(18, t.bodySize), weight: .medium)
        close.isHidden = pinned || !(isSelected || hovering)
        layer?.cornerRadius = t.cornerRadius
        layer?.borderWidth = t.borderWidth
        layer?.masksToBounds = false
        let state: (fill: NSColor, border: NSColor, text: NSColor, badge: NSColor, glyph: NSColor, glow: Bool)
        if isSelected { state = (t.accent, t.accent, t.accentText, t.accentText, t.accent, true) }
        else if hovering { state = (t.hover, t.accent, t.panelText, t.accent, t.iconGlyph, false) }
        else { state = (t.panel, t.panelBorder, t.panelText, t.iconBadge, t.iconGlyph, false) }
        fill.colors = AINCRADTheme.shade(state.fill)
        layer?.borderColor = state.border.cgColor
        label.textColor = state.text
        close.contentTintColor = state.text
        badge.backgroundColor = state.badge.cgColor
        icon.contentTintColor = hasFavicon ? nil : state.glyph
        if state.glow {
            layer?.shadowColor = t.accent.cgColor; layer?.shadowOpacity = t.glowOpacity
            layer?.shadowRadius = t.glow; layer?.shadowOffset = .zero
        } else {
            layer?.shadowColor = t.shadowColor.cgColor; layer?.shadowOpacity = t.shadowOpacity
            layer?.shadowRadius = t.shadowRadius; layer?.shadowOffset = CGSize(width: 0, height: -2)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { onSelect?() }
    override func otherMouseUp(with event: NSEvent) { if event.buttonNumber == 2 { onClose?() } }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func closeTapped() { onClose?() }
}

/// A launcher circle: gradient fill, themed border, an accent ring when hovered, accent fill and glow when
/// selected, the icon at 46% of the diameter in the theme's icon colour. Same states as the launcher's.
final class CircleButton: NSControl {
    var image: NSImage? { didSet { renderIcon() } }
    var isSelected = false { didSet { restyle() } }
    /// Colour used for the hover ring and tint instead of the theme accent (the window buttons use their own).
    var hoverColor: () -> NSColor? = { nil }
    private(set) var factor: CGFloat = 1

    private let fill = CAGradientLayer()
    private let ring = CALayer()
    private let iconLayer = CALayer()
    private var hovering = false { didSet { restyle() } }
    private var pressed = false { didSet { restyle() } }
    private var widthC: NSLayoutConstraint?
    private var heightC: NSLayoutConstraint?
    private var lastTint: NSColor?

    override var isEnabled: Bool { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    override var toolTip: String? { didSet { setAccessibilityLabel(toolTip) } }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    convenience init(factor: CGFloat) { self.init(frame: .zero); self.factor = factor; updateSize() }
    convenience init() { self.init(frame: .zero) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        fill.masksToBounds = true
        layer?.addSublayer(fill)
        layer?.addSublayer(ring)
        layer?.addSublayer(iconLayer)
        iconLayer.contentsGravity = .resizeAspect
        widthC = widthAnchor.constraint(equalToConstant: AINCRADTheme.buttonSize)
        heightC = heightAnchor.constraint(equalToConstant: AINCRADTheme.buttonSize)
        widthC?.isActive = true; heightC?.isActive = true
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func updateSize() {
        let d = (AINCRADTheme.buttonSize * factor).rounded()
        widthC?.constant = d; heightC?.constant = d
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let d = bounds.width
        layer?.cornerRadius = d / 2
        fill.frame = bounds
        fill.cornerRadius = d / 2
        ring.frame = bounds.insetBy(dx: -5, dy: -5)
        ring.cornerRadius = (d + 10) / 2
        let s = (d * 0.46).rounded()
        iconLayer.frame = CGRect(x: (d - s) / 2, y: (d - s) / 2, width: s, height: s)
        layer?.shadowPath = CGPath(ellipseIn: bounds, transform: nil)
        restyle()
    }

    func restyle() {
        let t = AINCRADTheme.self
        let accent = hoverColor() ?? t.accent
        let tint: NSColor
        layer?.borderWidth = t.borderWidth
        layer?.borderColor = t.circleBorder.cgColor
        ring.borderWidth = t.ringWidth
        ring.borderColor = accent.cgColor
        if isSelected {
            fill.colors = AINCRADTheme.shade(accent)
            ring.opacity = 1
            tint = t.accentText
            layer?.shadowColor = accent.cgColor; layer?.shadowOpacity = t.glowOpacity
            layer?.shadowRadius = t.glow; layer?.shadowOffset = .zero
        } else if hovering || pressed {
            fill.colors = AINCRADTheme.shade(t.hover)
            ring.opacity = 0.6
            tint = accent
            normalShadow()
        } else {
            fill.colors = AINCRADTheme.shade(t.circle)
            ring.opacity = 0
            tint = t.circleIcon
            normalShadow()
        }
        if lastTint != tint { lastTint = tint; renderIcon() }
    }

    private func normalShadow() {
        let t = AINCRADTheme.self
        layer?.shadowColor = t.shadowColor.cgColor; layer?.shadowOpacity = t.shadowOpacity
        layer?.shadowRadius = t.shadowRadius; layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    private func renderIcon() {
        guard let image, let tint = lastTint ?? Optional(AINCRADTheme.circleIcon) else { iconLayer.contents = nil; return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let side = max(iconLayer.bounds.width, 12)
        let size = NSSize(width: side, height: side)
        let tinted = NSImage(size: size, flipped: false) { rect in
            let ratio = image.size.width / max(image.size.height, 1)
            var fit = rect
            if ratio > 1 { fit.size.height = rect.width / ratio; fit.origin.y = (rect.height - fit.height) / 2 }
            else { fit.size.width = rect.height * ratio; fit.origin.x = (rect.width - fit.width) / 2 }
            image.draw(in: fit)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        var rect = NSRect(origin: .zero, size: NSSize(width: side * scale, height: side * scale))
        iconLayer.contents = tinted.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        iconLayer.contentsScale = scale
    }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); lastTint = nil; restyle() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { if isEnabled { hovering = true } }
    override func mouseExited(with event: NSEvent) { hovering = false; pressed = false }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside, isEnabled { sendAction(action, to: target) }
    }
}
