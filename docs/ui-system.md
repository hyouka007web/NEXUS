# NEXUS UI System 2.0

## Design principle
**Chrome verschwindet, Content dominiert.** The UI uses the existing NEXUS/TUF token language: dark surfaces, restrained accent lines, 4dp spacing grid, 8–18dp panel radii, and no decorative animation that does not communicate state.

## Component hierarchy
```text
NexusFlutterApp
└── BrowserScreen
    ├── GlobalKeyboardLayer
    │   ├── Ctrl+K Command Palette
    │   ├── Ctrl+L Address reveal/focus
    │   └── user-defined command IDs
    ├── BrowserChrome (hidden in Frameless)
    │   ├── Brand / status / menu
    │   └── AddressBar
    ├── Sidebar
    │   ├── Navigation
    │   ├── Complete analysis
    │   ├── Video Harvester
    │   └── Library
    └── PaneTree
        ├── Pane
        │   ├── Browser + pane-local tabs
        │   ├── Terminal session
        │   └── DevTools
        └── Splitter
            ├── horizontal split
            └── vertical split
```

## State management
- `TabManager`: WebView controllers, URLs, navigation and tab persistence.
- `PaneManager`: recursive binary split tree, pane-local tab IDs, active pane, pane kind, splitter ratio and terminal session text.
- `WorkspaceManager`: named snapshots of tabs + pane tree + terminal sessions.
- `KeybindingEngine`: command ID → shortcut map, persisted JSON, profiles `Custom`, `Vim`, `Emacs`, `Gaming`.
- `ThemeConfig`: JSON-overridable colors, radii, spacing, fonts and `autoDarkWeb`.
- `DevSettings`: existing bookmarks/quick-links and developer settings.

Persistence lives in the app documents directory and does not require PocketBase.

## Command Palette
Floating modal, max 720×560dp, fuzzy subsequence matching. Categories include:
- **Tabs** — all open pane tabs.
- **Actions** — navigation, harvester, scraper, panes, workspace and tools.
- **Bookmarks** — DevSettings quick links.
- **History** — recent tab URLs exposed as history entries.
- **Settings** — Auto-Dark and keybinding profiles/editor.

## Split-view behavior
A pane can be split vertically or horizontally. The split ratio starts at 50/50 and can be dragged between 20/80 and 80/20. Tabs are owned by panes; switching panes switches the active WebView context.

## Frameless mode
`Ctrl+Shift+F` removes address bar, tab chrome and sidebar. A thin 18dp top hotspot reveals the address bar on hover; `Ctrl+L` reveals and focuses it. The web content remains full-screen.

## Theme JSON
Example file: `assets/nexus_theme.json`. A user override is loaded from the application documents directory as `theme.json`.

## Security note for terminal
Terminal execution is intentionally local to the Android app process. Commands are passed to `/system/bin/sh` as a user-controlled shell string; this feature must never accept commands from remote web content or untrusted pages.

## Wireframe
```text
NORMAL
┌──────────────────────────────────────────────────────────────┐
│ NEXUS                         shield 42       ⋮              │
│  [ <  URL / SEARCH .................................... ]   │
├──┬───────────────────────────────────────────────────────────┤
│  │ [tab A] [tab B] [+] [│] [═] [terminal] [devtools]        │
│S ├──────────────────────────────┬────────────────────────────┤
│I │                              │                            │
│D │          WEB CONTENT         │       TERMINAL / WEB       │
│E │                              │                            │
│  │                              │                            │
└──┴──────────────────────────────┴────────────────────────────┘

FRAMELESS
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│                       WEB CONTENT                            │
│                                                              │
│                Ctrl+L → chrome appears                       │
└──────────────────────────────────────────────────────────────┘

COMMAND PALETTE
┌──────────────────────────────────────────────────────────────┐
│ 🔎  command, tab, bookmark, history…                         │
├──────────────────────────────────────────────────────────────┤
│ Tabs       · GitHub — NEXUS                                  │
│ Actions    · Video Harvester starten                         │
│ Actions    · Vertikal splitten                               │
│ Bookmarks  · DuckDuckGo                                      │
│ Settings   · Keybindings / Vim / Emacs / Gaming              │
└──────────────────────────────────────────────────────────────┘
```
