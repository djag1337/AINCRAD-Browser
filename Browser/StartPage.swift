import Foundation

enum StartPage {
    private static var vars: String {
        let t = AINCRADTheme.self
        let bg = t.isDark ? "#0e1016" : "#e6e7ea"
        return ":root{--accent:\(t.css(t.accent));--panel:\(t.css(t.panel));--text:\(t.css(t.panelText));--border:\(t.css(t.panelBorder));--bg:\(bg);--body:'\(t.bodyFamily)';--display:'\(t.displayFamily)'}"
    }

    /// A new tab set to "blank": just the theme's background.
    static func blank() -> String {
        "<!doctype html><meta name='color-scheme' content='light dark'><style>\(vars)html{background:var(--bg)}</style>"
    }

    static func html(privateMode: Bool) -> String {
        let prefs = BrowserPrefsModel.shared.prefs
        let t = AINCRADTheme.self
        let heading = privateMode ? "PRIVATE LINK" : "AINCRAD BROWSER"
        let note = privateMode ? "<p class=\"note\">AINCRAD Browser won’t save this window’s history, cookies, or website data after it closes.</p>" : ""
        let store = BrowserStore.shared
        let orbs = privateMode || !prefs.showFavorites ? "" : orbRow(store.bookmarks.prefix(8).map { ($0.title, $0.url) })
        var seen = Set<String>()
        let recentItems = store.history.filter { seen.insert($0.url).inserted }.prefix(8).map { ($0.title, $0.url) }
        let recent = privateMode || !prefs.showRecent ? "" : cards(title: "Recently Visited", items: recentItems)
        let clock = prefs.showClock ? "<div class=\"clock panel\"><b id=\"t\"></b><span id=\"d\"></span></div>" : ""
        let template = (BrowserPrefs.engines.first { $0.id == prefs.searchEngine }?.template ?? (prefs.searchEngine == "custom" ? prefs.customSearchTemplate : BrowserPrefs.engines[0].template))
        let templateLiteral = (try? JSONEncoder().encode(template)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>\(fontFaces)
        \(vars)
        :root{font-family:var(--body),-apple-system,sans-serif;color:var(--text);background:var(--bg)}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(135deg,\(t.isDark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.72)"),transparent 42%),repeating-linear-gradient(0deg,transparent 0 31px,rgba(128,128,128,.05) 32px)}
        .br{position:fixed;width:30px;height:30px;border:0 solid var(--accent);filter:drop-shadow(0 0 5px var(--accent));opacity:.85}
        .br.a{top:14px;left:14px;border-width:3px 0 0 3px}.br.b{top:14px;right:14px;border-width:3px 3px 0 0}.br.c{bottom:14px;left:14px;border-width:0 0 3px 3px}.br.d{bottom:14px;right:14px;border-width:0 3px 3px 0}
        main{text-align:center;width:min(780px,84vw);padding:60px 0}
        .mark{width:74px;height:74px;border-radius:50%;margin:auto;background:var(--panel);border:2px solid var(--accent);box-shadow:0 8px 24px rgba(0,0,0,.18),0 0 18px var(--accent);display:grid;place-items:center;color:var(--accent);font:600 34px var(--display)}
        h1{font-family:var(--display),sans-serif;font-size:34px;letter-spacing:3px;margin:22px 0 26px}
        .note{font-size:15px;opacity:.65;margin:-10px 0 26px}
        form{margin:0 auto 34px;width:min(560px,100%)}
        input{width:100%;box-sizing:border-box;padding:14px 20px;font:600 18px var(--body);letter-spacing:.5px;color:var(--text);background:var(--panel);border:1px solid var(--accent);border-radius:4px;outline:none;box-shadow:0 4px 14px rgba(0,0,0,.1)}
        input:focus{box-shadow:0 0 16px var(--accent)}input::placeholder{color:var(--text);opacity:.45}
        .panel{background:var(--panel);border:1px solid var(--border);border-radius:4px;box-shadow:0 4px 12px rgba(0,0,0,.1)}
        .orbs{display:flex;flex-wrap:wrap;gap:22px;justify-content:center;margin:0 0 6px}
        .orb{display:block;width:84px;color:inherit;text-decoration:none;text-align:center}
        .orb i{display:grid;place-items:center;width:64px;height:64px;margin:0 auto 8px;border-radius:50%;background:var(--panel);border:1.5px solid var(--accent);font:600 24px var(--display);font-style:normal;color:var(--accent);box-shadow:0 4px 12px rgba(0,0,0,.14);transition:box-shadow .15s}
        .orb:hover i{box-shadow:0 0 18px var(--accent)}.orb em{display:block;font-style:normal;font-size:13px;opacity:.75;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        section{text-align:left;margin:26px 0}section h2{font-family:var(--display),sans-serif;font-size:12px;color:var(--accent);letter-spacing:1.5px;opacity:.7;margin:0 0 12px 4px}
        .grid{display:grid;grid-template-columns:repeat(4,1fr);gap:10px}.card{display:block;color:inherit;text-decoration:none;padding:15px 12px;border-radius:4px;background:var(--panel);border:1px solid var(--border);box-shadow:0 4px 12px rgba(0,0,0,.08);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.card:hover{border-color:var(--accent);box-shadow:0 0 12px var(--accent)}
        .clock{position:fixed;left:34px;bottom:34px;padding:12px 22px;text-align:left}@media (max-width:1000px),(max-height:760px){.clock{display:none}}.clock b{display:block;font:600 34px var(--display);letter-spacing:2px}.clock span{font-size:14px;opacity:.7}
        </style></head><body><i class="br a"></i><i class="br b"></i><i class="br c"></i><i class="br d"></i>
        <main><div class="mark">／</div><h1>\(heading)</h1>\(note)
        <form id="f"><input id="q" placeholder="Search or enter a website" autofocus autocomplete="off" spellcheck="false"></form>
        \(orbs)\(recent)</main>\(clock)
        <script>
        var T=\(templateLiteral);
        document.getElementById('f').onsubmit=function(e){e.preventDefault();var v=document.getElementById('q').value.trim();if(!v)return;
          if(/^[a-z][a-z0-9+.-]*:\\/\\//i.test(v))location.href=v;else if(/^[^\\s]+\\.[^\\s]{2,}$/.test(v))location.href='https://'+v;else location.href=T.replace('%s',encodeURIComponent(v));};
        function tick(){var n=new Date(),t=document.getElementById('t');if(!t)return;t.textContent=n.toLocaleTimeString([],{hour:'2-digit',minute:'2-digit',hour12:false});document.getElementById('d').textContent=n.toLocaleDateString([],{weekday:'long',month:'long',day:'numeric'});}
        tick();setInterval(tick,5000);
        </script></body></html>
        """
    }

    /// The first-run tour: what the bar does and where everything is.
    static func welcome() -> String {
        let steps: [(String, String, String)] = [
            ("⌄", "The bar lives at the bottom", "Move the pointer to the bottom edge and it slides up: window buttons, back and forward, your tabs, search, downloads, share and bookmark. It tucks away when you leave, so pages get the whole window."),
            ("⌕", "Search is a button", "Press the magnifier (or ⌘L) and the address pill opens over your tabs. Return or Esc puts the tabs back."),
            ("▤", "Tabs, bookmarks and history", "Tabs are pills (middle-click or ✕ closes, right-click for more). The books button, ⌘B and ⌘Y open bookmarks and history as a dropdown."),
            ("◎", "It matches AINCRAD", "The browser wears your launcher theme live. With AINCRAD installed, its Web circle lists your tabs and bookmarks and can open a new tab."),
            ("⚙", "Make it yours", "Settings (⌘,) has ad and tracker blocking, reader mode (⇧⌘R), dark pages, search engines, toolbar size, themes and more. Help › Keyboard Shortcuts lists every key."),
            ("🔒", "Private by design", "Private windows save nothing and are never shared with AINCRAD. The browser never reads your passwords; Apple Passwords handles sign-in."),
        ]
        let cards = steps.map { icon, title, body in
            "<div class='step panel'><i>\(icon)</i><div><b>\(escape(title))</b><p>\(escape(body))</p></div></div>"
        }.joined()
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <style>\(fontFaces)
        \(vars)
        :root{font-family:var(--body),-apple-system,sans-serif;color:var(--text);background:var(--bg)}
        body{margin:0;min-height:100vh;display:grid;place-items:center;background:linear-gradient(135deg,\(AINCRADTheme.isDark ? "rgba(255,255,255,.06)" : "rgba(255,255,255,.72)"),transparent 42%)}
        main{width:min(820px,88vw);padding:48px 0}
        h1{font-family:var(--display),sans-serif;font-size:32px;letter-spacing:3px;text-align:center;margin:0 0 6px}
        .sub{text-align:center;opacity:.7;font-size:18px;margin:0 0 30px;letter-spacing:.5px}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:14px}
        .panel{background:var(--panel);border:1px solid var(--border);border-radius:4px;box-shadow:0 4px 12px rgba(0,0,0,.1)}
        .step{display:flex;gap:14px;padding:16px;align-items:flex-start}
        .step i{flex:none;width:44px;height:44px;border-radius:50%;display:grid;place-items:center;border:1.5px solid var(--accent);color:var(--accent);font:600 20px var(--display);font-style:normal;box-shadow:0 0 10px var(--accent)}
        .step b{font-family:var(--display),sans-serif;font-size:13px;letter-spacing:1px;color:var(--accent)}
        .step p{margin:6px 0 0;font-size:16px;line-height:1.35}
        .go{display:block;margin:30px auto 0;width:max-content;padding:14px 38px;border-radius:30px;background:var(--accent);color:#fff;text-decoration:none;font:600 20px var(--display);letter-spacing:2px;box-shadow:0 0 18px var(--accent)}
        </style></head><body><main>
        <h1>WELCOME TO AINCRAD BROWSER</h1><p class="sub">A quick tour. You can replay it any time from Settings.</p>
        <div class="grid">\(cards)</div>
        <a class="go" href="aincrad-browser://done">START BROWSING</a>
        </main></body></html>
        """
    }

    private static func orbRow(_ items: [(String, String)]) -> String {
        let orbs = items.map { title, url in
            let letter = escape(String((title.first(where: { $0.isLetter || $0.isNumber }) ?? "/")).uppercased())
            return "<a class='orb' href='\(escape(url))'><i>\(letter)</i><em>\(escape(title))</em></a>"
        }.joined()
        return orbs.isEmpty ? "" : "<div class='orbs'>\(orbs)</div>"
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

