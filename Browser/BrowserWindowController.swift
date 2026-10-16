import AppKit

final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let browser: BrowserViewController
    var onClose: (() -> Void)?

    init(privateMode: Bool, restoredState: WindowState?) {
        browser = BrowserViewController(privateMode: privateMode, restoredState: restoredState)
        let window = NSWindow(
            contentRect: BrowserWindowController.defaultFrame(),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = privateMode ? "Private — AINCRAD Browser" : "AINCRAD Browser"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 980, height: 560)
        // See-through behind the floating bar; the page panel and buttons carry their own surfaces.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.tabbingMode = .disallowed
        window.contentViewController = browser
        // Attaching a view controller shrinks the window to the view's tiny natural size, so set the real one after.
        window.setContentSize(BrowserWindowController.defaultFrame().size)
        super.init(window: window)
        window.delegate = self
        if BrowserPrefsModel.shared.prefs.rememberWindowSize, !BrowserWindowController.resetOldFrames, let rawFrame = restoredState?.frame {
            let restored = NSRectFromString(rawFrame)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restored) }) { window.setFrame(restored, display: false) } else { window.center() }
        } else { window.center() }
    }

    /// Frames saved before the bigger default (version 0.8) are ignored once, so everyone gets the new size.
    private static let resetOldFrames: Bool = {
        let key = "didResetWindowFramesV08"
        if UserDefaults.standard.bool(forKey: key) { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }()

    /// The size a new window opens at: about 80% of the screen by default (never smaller than 1100×720), or compact/large.
    static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        switch BrowserPrefsModel.shared.prefs.windowSize {
        case "compact": return NSRect(x: 0, y: 0, width: min(1000, screen.width), height: min(680, screen.height))
        case "large": return NSRect(x: 0, y: 0, width: min(1440, screen.width * 0.94), height: min(940, screen.height * 0.94))
        default: return NSRect(x: 0, y: 0, width: min(max(1100, screen.width * 0.8), screen.width), height: min(max(720, screen.height * 0.8), screen.height))
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidMove(_ notification: Notification) { NotificationCenter.default.post(name: .browserWindowStateChanged, object: nil) }
    func windowDidResize(_ notification: Notification) { NotificationCenter.default.post(name: .browserWindowStateChanged, object: nil) }
    func windowState() -> WindowState {
        var state = browser.windowState(); state.frame = window.map { NSStringFromRect($0.frame) }; return state
    }
}

