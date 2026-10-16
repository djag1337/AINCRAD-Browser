import AppKit
import WebKit

final class BrowserTab: NSObject {
    let webView: WKWebView
    var pinned = false
    var title = "Start Page"
    var lastCommittedURL: URL?
    var icon: NSImage?

    init(privateMode: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = privateMode ? .nonPersistent() : .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        BrowserFeatures.shared.creationConfiguration(configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        BrowserFeatures.shared.configure(self)
    }

    var state: TabState {
        TabState(url: webView.url?.absoluteString ?? "glass://start", title: title, pinned: pinned)
    }
}

