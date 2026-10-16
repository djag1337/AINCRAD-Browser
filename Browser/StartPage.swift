import Foundation

enum StartPage {
    static func html(privateMode: Bool) -> String {
        let heading = privateMode ? "PRIVATE LINK" : "AINCRAD BROWSER"
        let player = AINCRADTheme.playerName.trimmingCharacters(in: .whitespaces)
        let message = privateMode
            ? "AINCRAD Browser won’t save this window’s history, cookies, or website data after it closes."
            : (player.isEmpty ? "LINK START." : "WELCOME BACK, \(escape(player.uppercased())). LINK START.")
        let t = AINCRADTheme.self
        let bg = t.isDark ? "#0e1016" : "#e6e7ea"
        let vars = ":root{--accent:\(t.css(t.accent));--panel:\(t.css(t.panel));--text:\(t.css(t.panelText));--border:\(t.css(t.panelBorder));--bg:\(bg);--sheen:\(t.isDark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.72)");--body:'\(t.bodyFamily)';--display:'\(t.displayFamily)'}"
        let store = BrowserStore.shared
        let favorites = privateMode || !store.showFavoritesOnStartPage ? "" : cards(title: "Favorites", items: store.bookmarks.prefix(8).map { ($0.title, $0.url) })
        var seen = Set<String>()
        let recentItems = store.history.filter { seen.insert($0.url).inserted }.prefix(8).map { ($0.title, $0.url) }
        let recent = privateMode || !store.showRecentOnStartPage ? "" : cards(title: "Recently Visited", items: recentItems)
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>\(fontFaces)
        \(vars)
        :root{font-family:var(--body),-apple-system,sans-serif;color:var(--text);background:var(--bg)}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(135deg,var(--sheen),transparent 42%),repeating-linear-gradient(0deg,transparent 0 31px,rgba(128,128,128,.05) 32px)}
        main{text-align:center;width:min(760px,84vw);padding:70px 0}
        .mark{width:74px;height:74px;border-radius:50%;margin:auto;background:var(--panel);border:2px solid var(--accent);box-shadow:0 8px 24px rgba(0,0,0,.18),0 0 18px var(--accent);display:grid;place-items:center;color:var(--accent);font-size:34px;font-weight:700}
        h1{font-family:var(--display),sans-serif;font-size:36px;letter-spacing:2px;margin:24px 0 8px}p{font-size:17px;letter-spacing:1px;opacity:.65;margin:0}
        .hint{margin:38px 0;font-size:13px;opacity:.42}kbd{font:inherit;padding:3px 7px;border-radius:6px;background:rgba(128,128,128,.16)}
        section{text-align:left;margin:30px 0}section h2{font-family:var(--display),sans-serif;font-size:12px;color:var(--accent);letter-spacing:1.5px;opacity:.62;margin:0 0 12px 4px}.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.card{display:block;color:inherit;text-decoration:none;padding:15px 12px;border-radius:4px;background:var(--panel);border:1px solid var(--border);box-shadow:0 4px 12px rgba(0,0,0,.08);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.card:hover{border-color:var(--accent);box-shadow:0 0 12px var(--accent)}
        </style></head><body><main><div class="mark">／</div><h1>\(heading)</h1><p>\(message)</p><div class="hint">Press <kbd>⌘L</kbd> to search or enter a website</div>\(favorites)\(recent)</main></body></html>
        """
    }

    /// Web pages can't see fonts the app registers, so the bundled SAO fonts go in as data URLs (built once).
    private static let fontFaces: String = {
        let files = [("Orbitron", "Orbitron-wght", "400 900"), ("Rajdhani", "Rajdhani-Medium", "500"), ("Rajdhani", "Rajdhani-Bold", "600 700")]
        return files.compactMap { family, file, weight in
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf") ?? Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts"),
                  let data = try? Data(contentsOf: url) else { return nil }
            return "@font-face{font-family:'\(family)';font-weight:\(weight);src:url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype')}"
        }.joined()
    }()

    private static func cards<S: Sequence>(title: String, items: S) -> String where S.Element == (String, String) {
        let links = items.map { "<a class='card' href='\(escape($0.1))'>\(escape($0.0))</a>" }.joined()
        return links.isEmpty ? "" : "<section><h2>\(escape(title))</h2><div class='grid'>\(links)</div></section>"
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "'", with: "&#39;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}

