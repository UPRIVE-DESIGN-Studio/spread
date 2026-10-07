# Spread

A tiny macOS menu bar app that tiles **all windows of one app** into an even grid, on one screen or across all of them.

Personal tool: no Dock icon, no network access, ~0% CPU when idle. macOS 14+.

## Shortcuts

| Shortcut | What it does |
|---|---|
| Tap `⌃⌥⌘` (press and release on their own) | Tile the frontmost app onto the screen under the mouse |
| `⌃⌥⌘A` | Spread the frontmost app's windows across **all** screens |
| `⌃⌥T` | Tile the frontmost app onto the screen chosen in the menu |
| `⌃⌥Z` | Undo the last tile (exact previous frames) |

All except the `⌃⌥⌘` tap can be changed in Settings; the tap can be switched off there.

## Menu

- Every app with tileable windows, with its window count, e.g. `Google Chrome (5)`. Click to tile it.
- **Tile Onto** (with two or more screens): screen under mouse, a specific monitor, all screens, or each screen in place.
- Undo, Settings, Quit.

## How the grid works

The column count is picked per screen shape so cells stay close to a 1.2 aspect ratio: 5 windows on 16:9 become 3 on top and 2 wider below, with no holes. Windows go to cells in reading order based on where they are now, so they move as little as possible. Across several screens, each screen gets a share of the windows proportional to its usable area.

Only standard windows on the current Space are tiled. Sheets, dialogs, panels, full-screen and (by default) minimized windows are left alone.

## Build

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make test      # unit tests (grid, coordinates, screen split, ⌃⌥⌘ tap)
make run       # build and launch the Debug app
make install   # Release build into /Applications (needed for launch at login)
```

`project.yml` is the source of truth; the `.xcodeproj` is generated. Signing uses an Apple Development certificate so the Accessibility permission survives rebuilds; change `DEVELOPMENT_TEAM` in `project.yml` to your own team.

On first launch, grant Accessibility access when asked (System Settings › Privacy & Security › Accessibility).
