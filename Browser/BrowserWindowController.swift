import AppKit

final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let browser: BrowserViewController
    var onClose: (() -> Void)?

    init(privateMode: Bool, restoredState: WindowState?) {
        browser = BrowserViewController(privateMode: privateMode, restoredState: restoredState)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = privateMode ? "Private — AINCRAD Browser" : "AINCRAD Browser"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 720, height: 480)
        window.backgroundColor = .windowBackgroundColor
        window.tabbingMode = .disallowed
        window.contentViewController = browser
        super.init(window: window)
        window.delegate = self
        if let rawFrame = restoredState?.frame {
            let restored = NSRectFromString(rawFrame)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(restored) }) { window.setFrame(restored, display: false) } else { window.center() }
        } else { window.center() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidMove(_ notification: Notification) { NotificationCenter.default.post(name: .browserWindowStateChanged, object: nil) }
    func windowDidResize(_ notification: Notification) { NotificationCenter.default.post(name: .browserWindowStateChanged, object: nil) }
    func windowState() -> WindowState {
        var state = browser.windowState(); state.frame = window.map { NSStringFromRect($0.frame) }; return state
    }
}

