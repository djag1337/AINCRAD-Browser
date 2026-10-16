import AppKit
import WebKit

/// Everything the Settings page can switch on, applied to tabs: tracker blocking, user CSS and dark pages,
/// the user-agent and zoom, HTTPS upgrades, link cleaning, popup control and reader mode.
final class BrowserFeatures {
    static let shared = BrowserFeatures()
    private var prefs: BrowserPrefs { BrowserPrefsModel.shared.prefs }

    private var ruleList: WKContentRuleList?
    private var ruleListKey = ""
    private var compiling = false
    private var lastInput = Date.distantPast
    private var inputMonitor: Any?

    /// Starts watching for real clicks and keys, so a page's own pop-ups can be told from ones you asked for.
    func start() {
        inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown, .rightMouseDown]) { [weak self] event in
            self?.lastInput = Date(); return event
        }
        refreshRuleList()
    }

    /// True when you clicked or typed in the last moment (so a pop-up is probably wanted).
    var userJustActed: Bool { Date().timeIntervalSince(lastInput) < 1.5 }

    // MARK: Applying to a tab

    func configure(_ tab: BrowserTab) {
        let web = tab.webView
        web.customUserAgent = prefs.userAgentString
        if web.pageZoom == 1 || web.url == nil { web.pageZoom = CGFloat(prefs.defaultZoom) }
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        if let script = pageScript() { controller.addUserScript(script) }
        controller.removeAllContentRuleLists()
        if prefs.blockTrackers, let list = ruleList { controller.add(list) }
    }

    func creationConfiguration(_ configuration: WKWebViewConfiguration) {
        configuration.mediaTypesRequiringUserActionForPlayback = prefs.blockAutoplay ? .all : []
    }

    /// Re-applies the content rules after a preference changed (recompiling only if the block list did).
    func prefsChanged() { refreshRuleList() }

    // MARK: Pages: user CSS and dark mode

    private func pageScript() -> WKUserScript? {
        var css = prefs.userCSS
        if prefs.darkPages {
            css += "\nhtml{filter:invert(1) hue-rotate(180deg)!important;background:#fff}img,video,picture,canvas,iframe,svg image{filter:invert(1) hue-rotate(180deg)!important}"
        }
        guard !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = try? JSONEncoder().encode(css), let literal = String(data: data, encoding: .utf8) else { return nil }
        let source = "if(location.protocol!=='glass:'){var s=document.createElement('style');s.id='ainc-user';s.textContent=\(literal);(document.head||document.documentElement).appendChild(s);}"
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: Tracker blocking

    private static let builtInDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com", "googletagmanager.com", "googletagservices.com",
        "adservice.google.com", "facebook.net", "connect.facebook.net", "adnxs.com", "adsrvr.org", "advertising.com", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com", "scorecardresearch.com", "quantserve.com", "hotjar.com", "mixpanel.com", "segment.io", "segment.com",
        "amplitude.com", "fullstory.com", "mouseflow.com", "crazyegg.com", "optimizely.com", "newrelic.com", "nr-data.net", "pubmatic.com",
        "rubiconproject.com", "openx.net", "casalemedia.com", "smartadserver.com", "moatads.com", "adsafeprotected.com", "2mdn.net", "bluekai.com",
        "demdex.net", "omtrdc.net", "everesttech.net", "krxd.net", "tapad.com", "bidswitch.net", "sharethrough.com", "yieldmo.com", "amazon-adsystem.com",
        "ads-twitter.com", "analytics.twitter.com", "ads.linkedin.com", "px.ads.linkedin.com", "snap.licdn.com", "analytics.tiktok.com", "ads.tiktok.com",
        "bat.bing.com", "clarity.ms", "hs-analytics.net", "hsadspixel.net", "pardot.com", "marketo.net", "mktoresp.com", "chartbeat.com", "chartbeat.net",
        "parsely.com", "branch.io", "adjust.com", "appsflyer.com", "kochava.com", "onetrust.com", "cookielaw.org", "trustarc.com", "quantcount.com",
        "zedo.com", "revcontent.com", "mgid.com", "adform.net", "yandex.ru/metrika", "mc.yandex.ru", "ml314.com", "rlcdn.com", "liadm.com", "id5-sync.com",
    ]

    private func refreshRuleList() {
        guard prefs.blockTrackers else {
            if ruleList != nil { ruleList = nil; ruleListKey = ""; announce() }
            return
        }
        let domains = Self.builtInDomains + prefs.blockedDomains
        let key = "ainc-" + String(domains.joined(separator: ",").hashValue.magnitude, radix: 36)
        if key == ruleListKey && ruleList != nil { return }
        guard !compiling else { return }
        compiling = true
        let rules: [[String: Any]] = domains.map { d in
            let escaped = d.replacingOccurrences(of: ".", with: "\\.").replacingOccurrences(of: "/", with: "/")
            return ["trigger": ["url-filter": escaped, "load-type": ["third-party"]], "action": ["type": "block"]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { compiling = false; return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: key, encodedContentRuleList: json) { [weak self] list, error in
            DispatchQueue.main.async {
                self?.compiling = false
                if let list { self?.ruleList = list; self?.ruleListKey = key; self?.announce() }
                else if let error { NSLog("AINCRAD Browser: tracker rules failed to compile: \(error.localizedDescription)") }
            }
        }
    }

    private func announce() { NotificationCenter.default.post(name: .browserFeaturesReady, object: nil) }

    // MARK: Link handling

    private static let trackingParams: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_eid", "mc_cid", "_hsenc", "_hsmi", "igshid", "yclid", "twclid", "wbraid", "gbraid",
        "vero_id", "oly_enc_id", "oly_anon_id", "ttclid", "li_fat_id", "mkt_tok",
    ]

    /// The same link without tracking tags, or nil if it had none (or the option is off).
    func cleaned(_ url: URL) -> URL? {
        guard prefs.stripTrackingParams, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = parts.queryItems, !items.isEmpty else { return nil }
        let kept = items.filter { !($0.name.hasPrefix("utm_") || Self.trackingParams.contains($0.name.lowercased())) }
        guard kept.count != items.count else { return nil }
        parts.queryItems = kept.isEmpty ? nil : kept
        return parts.url
    }

    /// The https version of a plain http link (nil for local addresses, ports and when the option is off).
    func upgraded(_ url: URL) -> URL? {
        guard prefs.upgradeHTTPS, url.scheme == "http", let host = url.host?.lowercased(), url.port == nil else { return nil }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".localhost") || host.hasSuffix(".test") { return nil }
        if host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return nil }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = "https"
        return parts?.url
    }

    // MARK: Reader mode

    func readerScript() -> String {
        let t = AINCRADTheme.self
        let font = prefs.readerSerif ? "Georgia,\"Times New Roman\",serif" : "\"\(t.bodyFamily)\",-apple-system,sans-serif"
        return """
        (function(){
          var old=document.getElementById('ainc-reader'); if(old){old.remove();document.documentElement.style.overflow='';return 'closed';}
          function score(d){var n=0;d.querySelectorAll('p').forEach(function(p){n+=p.textContent.trim().length});return n}
          var root=document.body,best=0;
          document.querySelectorAll('article,main,[role=main],section,div').forEach(function(d){
            var sc=score(d); if(sc>best||(sc>=best*0.9&&sc>0&&root.contains(d))){best=Math.max(sc,best);root=d}});
          var clone=root.cloneNode(true);
          clone.querySelectorAll('script,style,nav,aside,footer,form,iframe,button,svg,noscript,link,[aria-hidden=true],table.infobox,.navbox,.mw-editsection,.reference,sup.reference,.toc,#toc').forEach(function(e){e.remove()});
          clone.querySelectorAll('ul,ol').forEach(function(l){var t=l.textContent.trim().length,a=0;l.querySelectorAll('a').forEach(function(x){a+=x.textContent.length});if(!l.querySelector('p')&&t>0&&a/t>0.7)l.remove()});
          clone.querySelectorAll('*').forEach(function(e){e.removeAttribute('style');e.removeAttribute('class');e.removeAttribute('id');e.removeAttribute('onclick')});
          var h1=document.querySelector('h1'); var title=(h1?h1.textContent:document.title).trim();
          var o=document.createElement('div'); o.id='ainc-reader';
          o.style.cssText='position:fixed;inset:0;z-index:2147483647;overflow:auto;background:\(t.css(t.panel.withAlphaComponent(1)));color:\(t.css(t.panelText));filter:none;';
          var s=document.createElement('style');
          s.textContent='#ainc-reader{filter:none!important}#ainc-reader *{box-sizing:border-box;filter:none!important}#ainc-reader .col{max-width:\(Int(prefs.readerWidth))px;margin:0 auto;padding:64px 28px 120px;font:\(Int(prefs.readerFontSize))px/1.7 \(font)}#ainc-reader h1{font:600 \(Int(prefs.readerFontSize) + 14)px/1.2 \\'\(t.displayFamily)\\',sans-serif;letter-spacing:1px;margin:0 0 .6em;color:\(t.css(t.accent))}#ainc-reader h2,#ainc-reader h3{font-family:\\'\(t.displayFamily)\\',sans-serif;margin:1.6em 0 .5em}#ainc-reader img{max-width:100%;height:auto;border-radius:6px}#ainc-reader a{color:\(t.css(t.accent))}#ainc-reader blockquote{border-left:3px solid \(t.css(t.accent));margin:1em 0;padding:.2em 1em;opacity:.85}#ainc-reader pre{overflow:auto;padding:12px;background:rgba(128,128,128,.15);border-radius:6px;font-size:.8em}#ainc-reader .x{position:fixed;top:16px;right:20px;width:36px;height:36px;border-radius:50%;border:1px solid \(t.css(t.accent));background:transparent;color:inherit;font-size:18px;cursor:pointer}';
          var col=document.createElement('div'); col.className='col';
          var h=document.createElement('h1'); h.textContent=title; col.appendChild(h);
          var first=clone.querySelector('h1'); if(first&&first.textContent.trim()===title)first.remove();
          col.appendChild(clone);
          var x=document.createElement('button'); x.className='x'; x.textContent='✕'; x.onclick=function(){o.remove();document.documentElement.style.overflow='';};
          o.appendChild(s); o.appendChild(col); o.appendChild(x);
          document.documentElement.appendChild(o); document.documentElement.style.overflow='hidden';
          return 'opened';
        })()
        """
    }
}

extension Notification.Name {
    static let browserFeaturesReady = Notification.Name("AINCRADBrowserFeaturesReady")
}
