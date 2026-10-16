# AINCRAD Browser

AINCRAD Browser is a lightweight, native macOS browser with a Safari-inspired layout and the established AINCRAD visual system. It uses the WebKit framework already included with macOS, so the application bundle stays small and no browser engine source checkout is required.

## Features you can customise

All of these live in one settings page. With AINCRAD installed it's **AINCRAD Settings › Browser**
(⌘, in the browser opens it); without AINCRAD the same page opens in the browser.

- **Ad and tracker blocking** (WebKit content rules, nothing leaves your Mac) plus your own block list
- **https upgrades** with automatic fallback, **tracking-tag stripping** (utm_, fbclid, gclid…), pop-up and autoplay control
- **Reader mode** (⌘⇧R) in your theme's colours, with text size, width and serif or sans
- **Dark mode for every page**, default page zoom, your own CSS on every page
- **Search engines** (DuckDuckGo, Google, Bing, Brave, Ecosia, Startpage, Kagi or your own URL)
- **Appear as** Safari, Chrome, Firefox or iPhone to sites that care
- **Start page**: HUD brackets, favourites as circles, recent sites, a clock, all optional; new tabs can open blank
- Pinned tabs, tab reordering and duplication, session restore (optional), private windows

## Keyboard shortcuts

| | |
|---|---|
| New tab / close tab / reopen closed tab | ⌘T / ⌘W / ⇧⌘T |
| Next / previous tab | ⌃Tab or ⇧⌘] / ⌃⇧Tab or ⇧⌘[ |
| Tab by number / last tab | ⌘1…⌘8 / ⌘9 |
| Address bar, reload, hard reload, stop | ⌘L, ⌘R, ⌥⌘R, ⌘. |
| Back / forward | ⌘[ / ⌘] |
| Find, next, previous | ⌘F, ⌘G, ⇧⌘G |
| Reader mode | ⇧⌘R |
| Bookmark, bookmarks, history, downloads, sidebar | ⌘D, ⌘B, ⌘Y, ⌘J, ⌘S |
| Zoom | ⌘+, ⌘-, ⌘0 |
| Close window | ⇧⌘W |

Tabs have a ✕ on the selected or hovered tab; middle-click closes; right-click offers Close Others, Close to the Right, Pin and Duplicate. Help › Keyboard Shortcuts lists them in the app.

## Looks and themes

By default the browser wears AINCRAD's current theme, so the launcher, widgets and browser match. In Settings › Browser › Look you can give the browser its own theme, which it keeps whatever the launcher does. New windows open at about 80% of the screen (or Compact / Large).

## Notarisation

Releases are currently signed with a development certificate and **not notarised**. Installed through AINCRAD's switch they open normally. If you download the zip in a web browser instead, macOS may say the developer can't be verified: right-click the app and choose Open once. `scripts/release.sh` notarises automatically when a Developer ID certificate and a `NOTARY_PROFILE` are available (see the header of the script).

## Works with AINCRAD

AINCRAD Browser is its own app and works fine alone. When [AINCRAD](https://github.com/djag1337/AINCRAD)
is installed too, the two respond to each other:

- **Same look.** The browser reads AINCRAD's active theme (colours, Orbitron/Rajdhani fonts) and
  your player name, and repaints the moment you switch themes in AINCRAD.
- **Tabs in the launcher.** AINCRAD's Files › AINCRAD Browser lists your open tabs (click one to
  jump to it), bookmarks and history, plus New Tab and New Private Window.
- **Links.** Web links opened from the launcher go to AINCRAD Browser (a switch in AINCRAD's settings).
- **Download bubbles.** Finished downloads show up as SAO notification bubbles.
- **◎ button.** Opens the AINCRAD launcher from the toolbar (hidden when AINCRAD isn't installed).
- **One settings page.** The browser's settings are a page of AINCRAD Settings.
- **Opt-in install.** In AINCRAD Settings › Browser, turning on *Use AINCRAD Browser* asks, then downloads the release from this repo's GitHub Releases and installs it. Nothing downloads until you approve; removing it moves it to the Trash.

No macOS permissions are involved. The browser writes a small file,
`~/Library/Application Support/AINCRAD Browser/link.json` (tab titles and addresses, 40 bookmarks,
20 recent sites), and both apps announce changes with local distributed notifications. Nothing
leaves your Mac. **Private windows are never shared**: their tabs, history and downloads stay out.

The browser also answers `aincrad-browser://open?url=…`, `aincrad-browser://tab?window=0&index=1`,
`aincrad-browser://new` and `aincrad-browser://private`.

## Included

- Native Intel (`x86_64`) macOS app targeting macOS 13 or later
- Multiple tabs and windows, private windows, session restoration, recently closed tabs
- Address/search field using DuckDuckGo, navigation controls, trackpad history gestures
- Bookmarks and history sidebar
- Bookmark removal plus Safari-compatible HTML import and export
- Searchable bookmark and history collections
- Start Page favorites and deduplicated recent sites, configurable in Settings
- Website favicons in tabs when sites provide them
- Remembered per-site camera and microphone decisions with a permissions manager
- Apple Passwords, passkeys, and verification-code flows supplied by the system WebKit experience
- Settings for search provider, history clearing, website-data clearing, and direct access to Passwords
- Downloads, page zoom, find-in-page, fullscreen, popup handling, and media permission prompts
- Download manager with cancel, Finder reveal, and finished-item clearing
- Live download percentage reporting
- Native share sheet, printing, copy-link, and Save as PDF
- Persistent normal browsing data and nonpersistent private browsing data
- A deliberately empty `ExtensionProvider` boundary for future extension work
- Window size and position restoration across displays

## Build

```bash
./scripts/build.sh
```

`./scripts/release.sh` builds `dist/AINCRAD-Browser.zip`, the file AINCRAD's installer downloads from the latest GitHub release.

This runs XcodeGen, builds Release into `~/Library/Caches/AINCRAD-Browser-build` (outside iCloud,
whose file attributes break code signing), and installs `/Applications/AINCRAD Browser.app`.
The app icon is drawn by `scripts/make_icon.swift`. Fonts: Orbitron and Rajdhani, SIL Open Font
License (see `Browser/Resources/Fonts`).

## Current boundaries

Chrome/Safari extensions, browser-owned password storage, cloud sync, DRM guarantees, automatic updates, notarization, and mobile versions are not included. Website compatibility and credential integration come from the macOS WebKit version installed on the machine. AINCRAD Browser intentionally does not copy credentials out of Apple Passwords.
