# Glow

A light, local-only macOS terminal that feels like Warp for the parts you
actually use — without the account, the cloud, the AI, or the GPU-heavy UI.

Built with **SwiftUI + SwiftTerm** (a PTY/VT emulator). No Electron, no
network, no sign-in.

## Run it

As a proper macOS app (recommended) — builds a release `Glow.app` and
installs it to `/Applications`, where Spotlight, Launchpad and the Dock
pick it up like any other app:

```sh
./Scripts/make-app.sh
open /Applications/Glow.app
```

Or run the bare executable during development:

```sh
swift run Glow
```

The app bundle is assembled from the SVG icon in `Design/` (rendered with
`Scripts/svg-to-png.swift` and packed into `AppIcon.icns` by `iconutil`).
No code signing is needed for local use.

## What's inside

- **One window per session**, tabs on top, folder sidebar on the left.
- **Tabs**: name them, color them, reorder by drag, close with the × (whole
  tab) or `Cmd+W` (focused pane, or the whole tab when it has one pane).
  Shortcuts: `Cmd+T` new tab, `Cmd+1`…`Cmd+9` select tab,
  `Cmd+Shift+[` / `Cmd+Shift+]` previous / next tab, `Cmd+Shift+T` reopen
  the last closed tab. Each tab has its own shell in its own folder.
- **Split panes**: several terminals inside one tab. `Cmd+D` split right,
  `Cmd+Shift+D` split down, `Cmd+Option+Arrow` move focus between panes,
  `Cmd+W` close the focused pane. The active pane gets a subtle accent
  border; click any pane to focus it. Split/close also live in the tab's
  right-click menu and the **Panes** menu.
- **Drag a tab to split**: grab a tab and drag it down onto the terminal.
  Dropping on your own tab's terminal splits it with a fresh shell; dropping
  on another tab's terminal moves that tab's shell into a split there. The
  highlighted half (left / right / top / bottom edge) shows where the new
  pane lands, and the drop zone indicator follows your cursor while dragging.
- **Folders**: sidebar shows Home + recent folders. `Open…` (`Cmd+O`)
  uses a folder picker. Double-click a folder, or drag one from Finder onto
  the sidebar or the tab bar — a new tab starts there. No `cd` needed.
  Dropping files (or folders) directly on a terminal inserts their
  shell-escaped paths into the shell, like the 📎 attach button — drag
  while typing `open `, `cd `, or a Grok `@path` mention around it.
- **Start command per tab**: right-click a tab → "Set Start Command…" to
  pin a folder + command (e.g. `grok`). The tab opens that folder and runs
  the command once the shell is ready. "Run Start Command" re-runs it.
- **Layouts**: `Cmd+Shift+S` saves the current tabs (names, colors,
  folders, start commands) as a named layout. The **Open Layout** menu
  restores one into a new window. Optionally auto-restore the last layout
  on launch (Settings).
- **Find in scrollback**: `Cmd+F`, `Cmd+G` / `Cmd+Shift+G`, Esc to close.
- **Clear scrollback**: `Cmd+K` (keeps the visible screen).
- **Font size**: `Cmd+=` / `Cmd+-` / `Cmd+0` to grow, shrink, or reset
  (also in Settings).
- **Copy last output**: `Cmd+Shift+C` (or the tab context menu) copies the
  last command plus its output — the text between the last Enter and the
  end of the scrollback.
- **Command-done notice**: when a tab's output goes quiet after running
  more than ~5s and Glow is in the background, the tab shows an orange dot
  and the Dock icon bounces once. Disable in Settings.
- **Global hotkey**: `Ctrl+`` shows/hides Glow (iTerm-style). Disable in
  Settings.
- **Appearance**: Settings (`Cmd+,`) — 9 themes (Dark, Light, Darker,
  Earth, RawBlock, Midnight, Sepia, Moss, Grok), font (SF Mono / Menlo /
  Monaco / Source Code Pro / Fira Code / Space Mono…), size 8–24.
  The look follows the ThoughtStream design system: warm neutrals (stone
  `#78716C` accent, warm black / warm white terminal), completely flat
  with sharp 0px edges, hairline borders instead of shadows, and generous
  spacing so the terminal reads like a well-set page.

## Where state lives

`~/Library/Application Support/Glow/glow-state.json` — recent folders,
layouts, and settings. That's the only file Glow writes.

## Known limitations (v1)

- Tab working directory is tracked from the shell's OSC 7 announcement
  when present; otherwise it's the folder the tab was started in. Layouts
  save the last known directory.
- Layouts save one tab per open tab (the focused pane's folder and start
  command); split-pane arrangements are not persisted yet.
- "Copy last output" is the simple last-prompt-to-end heuristic, not a
  full block engine.
- If you close the window entirely, the `Ctrl+`` hotkey re-activates Glow
  but doesn't recreate the window — press `Cmd+N` (Dock click also
  reopens it).
- TUI edge cases are up to SwiftTerm: most TUIs work; a rare one may look
  off. Fixing those is per-session work, not a renderer swap.

## Project layout

```
Sources/Glow/
  GlowApp.swift            app entry, menu commands, app delegate, Cmd+W / hotkey
  Models/                  AppModel (settings+persistence), WindowModel, TerminalSession, layout types
  Terminal/                GlowTerminalView (SwiftTerm subclass), TerminalHostView (SwiftUI bridge)
  Views/                   ContentView, TabBarView, FolderSidebarView, FindBarView, SettingsView
  Support/                 GlobalHotkey (Carbon), FolderDrop, color helpers
Design/                    SVG app icon source + generated AppIcon.icns
Scripts/                   make-app.sh (bundle builder), svg-to-png.swift (alpha-preserving SVG renderer)
```
# Glow
