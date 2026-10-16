# AINCRAD Browser

AINCRAD Browser is a lightweight, native macOS browser with a Safari-inspired layout and the established AINCRAD visual system. It uses the WebKit framework already included with macOS, so the application bundle stays small and no browser engine source checkout is required.

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

This runs XcodeGen, builds Release into `~/Library/Caches/AINCRAD-Browser-build` (outside iCloud,
whose file attributes break code signing), and installs `/Applications/AINCRAD Browser.app`.
The app icon is drawn by `scripts/make_icon.swift`. Fonts: Orbitron and Rajdhani, SIL Open Font
License (see `Browser/Resources/Fonts`).

## Current boundaries

Chrome/Safari extensions, browser-owned password storage, cloud sync, DRM guarantees, automatic updates, notarization, and mobile versions are not included. Website compatibility and credential integration come from the macOS WebKit version installed on the machine. AINCRAD Browser intentionally does not copy credentials out of Apple Passwords.
