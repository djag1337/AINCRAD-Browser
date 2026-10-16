import AppKit
import CoreText

/// AINCRAD's look, read live from AINCRAD's active theme (~/Library/Application Support/AINCRAD):
/// colours, accent and fonts follow whatever theme you pick there, and change the moment you switch.
/// Without AINCRAD installed, the browser uses Aincrad Classic (white and orange).
enum AINCRADTheme {
    static let changed = Notification.Name("AINCRADBrowserThemeChanged")

    private(set) static var accent = NSColor(srgbRed: 0.961, green: 0.651, blue: 0.137, alpha: 1)
    private(set) static var panel = NSColor(srgbRed: 0.969, green: 0.969, blue: 0.973, alpha: 0.98)
    private(set) static var panelText = NSColor(srgbRed: 0.263, green: 0.278, blue: 0.306, alpha: 1)
    private(set) static var panelBorder = NSColor.white.withAlphaComponent(0.9)
    private(set) static var footer = NSColor(srgbRed: 0.902, green: 0.906, blue: 0.918, alpha: 0.97)
    private(set) static var circle = NSColor(srgbRed: 0.973, green: 0.973, blue: 0.976, alpha: 0.95)
    private(set) static var hover = NSColor.white
    private(set) static var accentText = NSColor.white
    private(set) static var bodyFamily = "Rajdhani"
    private(set) static var displayFamily = "Orbitron"
    /// Your AINCRAD player name ("" if none is set).
    private(set) static var playerName = ""
    private(set) static var themeName = "Aincrad Classic"

    /// Light themes (white panels) or dark ones, judged from the panel colour.
    static var isDark: Bool { luminance(panel) < 0.5 }

    // Kept for the code that styled the dark chrome before themes were live.
    static var darkPanel: NSColor { panel }
    static var darkText: NSColor { panelText }

    /// The selected tab colour.
    static var tabBezel: NSColor { accent }

    private static var aincradFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AINCRAD", isDirectory: true)
    }

    /// Registers the bundled fonts, loads the theme, and listens for AINCRAD switching themes.
    static func start() {
        // Xcode flattens Resources/Fonts into the bundle root, so look in both places.
        for url in (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []) + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        reload()
        NotificationCenter.default.addObserver(forName: .browserPrefsChanged, object: nil, queue: .main) { _ in reload() }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.djag.aincrad.themeChanged"), object: nil, queue: .main) { _ in
            reload()
        }
        // A fallback for older AINCRAD builds that don't announce theme changes.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in reload() }
    }

    static func reload() {
        let before = signature
        var colors: [String: String] = [:], font: [String: Any] = [:]
        if let settings = json(aincradFolder.appendingPathComponent("settings.json")) ?? (BrowserPrefsModel.shared.prefs.theme != "follow" ? [:] : nil) {
            playerName = (settings["playerName"] as? String) ?? ""
            let chosen = BrowserPrefsModel.shared.prefs.theme
            let id = chosen != "follow" ? chosen : ((settings["theme"] as? String) ?? "aincrad-classic")
            if let theme = json(aincradFolder.appendingPathComponent("themes/\(id).json")) {
                colors = (theme["colors"] as? [String: String]) ?? [:]
                font = (theme["font"] as? [String: Any]) ?? [:]
                themeName = (theme["name"] as? String) ?? id
            }
        }
        accent = color(colors["accent"]) ?? NSColor(srgbRed: 0.961, green: 0.651, blue: 0.137, alpha: 1)
        panel = color(colors["panel"]) ?? NSColor(srgbRed: 0.969, green: 0.969, blue: 0.973, alpha: 0.95)
        panelText = color(colors["panelText"]) ?? NSColor(srgbRed: 0.263, green: 0.278, blue: 0.306, alpha: 1)
        panelBorder = color(colors["panelBorder"]) ?? NSColor.white.withAlphaComponent(0.9)
        footer = color(colors["infoFooter"]) ?? NSColor(srgbRed: 0.902, green: 0.906, blue: 0.918, alpha: 0.96)
        circle = color(colors["circle"]) ?? panel
        hover = color(colors["hover"]) ?? .white
        accentText = color(colors["accentText"]) ?? .white
        bodyFamily = (font["family"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Rajdhani"
        displayFamily = (font["display"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bodyFamily
        if signature != before { NotificationCenter.default.post(name: changed, object: nil) }
    }

    private static var signature: String {
        [accent, panel, panelText, footer].map { $0.description }.joined() + bodyFamily + displayFamily + playerName
    }

    private static func json(_ url: URL) -> [String: Any]? {
        (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    /// "#RRGGBB" or "#RRGGBBAA", as AINCRAD's themes write them.
    static func color(_ hex: String?) -> NSColor? {
        guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return nil }
        h.removeFirst()
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let a = h.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = h.count == 8 ? v >> 8 : v
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
    }

    static func css(_ c: NSColor) -> String {
        let s = c.usingColorSpace(.sRGB) ?? c
        return String(format: "rgba(%d,%d,%d,%.3f)", Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255), s.alphaComponent)
    }

    static func luminance(_ c: NSColor) -> CGFloat {
        let s = c.usingColorSpace(.sRGB) ?? c
        return 0.299 * s.redComponent + 0.587 * s.greenComponent + 0.114 * s.blueComponent
    }

    private static func font(_ family: String, _ size: CGFloat, weight: NSFont.Weight) -> NSFont? {
        let w = weight >= .semibold ? 9 : 6
        return NSFontManager.shared.font(withFamily: family, traits: [], weight: w, size: size) ?? NSFont(name: family, size: size)
    }

    static func displayFont(size: CGFloat) -> NSFont {
        font(displayFamily, size, weight: .semibold) ?? .systemFont(ofSize: size, weight: .semibold)
    }

    static func bodyFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        font(bodyFamily, size, weight: weight) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// The launcher's glass circle buttons.
    static func styleCircle(_ button: NSButton) {
        button.isBordered = false
        button.contentTintColor = panelText
        button.wantsLayer = true
        button.layer?.cornerRadius = 15
        button.layer?.backgroundColor = circle.cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = accent.withAlphaComponent(0.35).cgColor
    }

    static func makeMark(size: CGFloat = 24) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        accent.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: size - 4, height: size - 4))
        ring.lineWidth = max(1.5, size * 0.075)
        ring.stroke()
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: size * 0.31, y: size * 0.29))
        slash.line(to: NSPoint(x: size * 0.69, y: size * 0.71))
        slash.lineWidth = max(1.5, size * 0.075)
        slash.lineCapStyle = .round
        slash.stroke()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
