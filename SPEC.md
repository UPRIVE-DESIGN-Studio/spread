# BRIEF — "Spread" (working name)

A tiny macOS menu bar app that tiles **all windows of one app** into an even grid with a single click or hotkey.

Personal-use tool. No App Store, no accounts, no telemetry, no network access.

---

## 1. The problem

macOS can snap one or two windows, but there is no one-click way to say "take all 6 of my Chrome windows (or VS Code, Finder, Figma…) and spread them evenly across the screen." Rectangle (free) does one window at a time. Paid apps exist, but this is a weekend-sized build.

## 2. Core user flows (v1)

**Flow A — Menu bar click**
1. Click the menu bar icon.
2. The dropdown lists every running app that has at least one tileable window, with its icon, name and window count, e.g. `Google Chrome (5)`.
3. Click an app. All its tileable windows on the target screen arrange into an even grid. Done.

**Flow B — Hotkey on the frontmost app**
1. Press a global hotkey (default `⌃⌥T`, user-configurable).
2. All tileable windows of the **frontmost app** tile into the grid.

**Flow C — Undo**
1. Press `⌃⌥Z` (configurable) or choose "Undo last tile" in the menu.
2. Windows return to their exact previous frames.

## 3. Tiling rules

**Which windows count as tileable:**
- Role `AXWindow` with subrole `AXStandardWindow`. Exclude sheets, panels, dialogs, popovers and floating palettes.
- Not minimized. A setting can turn on "unminimize and include minimized windows"; it is off by default.
- Not in native full screen. Skip these silently.
- Only windows on the current Space (see §8).

**Target screen:**
- Default: the screen containing the **mouse pointer**.
- Setting: "Tile per screen". Each screen tiles the windows already on it, so no window moves between displays.
- Use the screen's `visibleFrame` so the menu bar and Dock are never covered.

**Grid algorithm** (n = number of windows):
- `cols = ceil(sqrt(n))`, `rows = ceil(n / cols)`.
- If the last row has fewer windows, those windows **widen to fill the row**, so there are no empty holes.
- Wide screens (aspect > 2.0, e.g. ultrawide): prefer more columns, e.g. `cols = ceil(sqrt(n * 1.5))`. Make this tunable.
- Example layouts: 1 = full, 2 = side by side, 3 = three columns (or 2+1 on narrow screens), 4 = 2×2, 5 = 3 on top + 2 wider below, 6 = 3×2.
- Gap between windows and the screen edge: setting, default **8 px**, range 0–24.

**Window order:**
- Assign windows to cells in reading order (top-left → bottom-right) based on their **current** positions, so windows move the shortest distance and the layout feels predictable.

**Windows that refuse a size:**
- Some apps enforce a minimum size. After setting a frame, read it back. If it doesn't match, keep the window's top-left corner in its cell and let it overflow. Don't fight it in a loop.

## 4. UI

- **Menu bar extra only.** No Dock icon (`LSUIElement = YES`).
- Dropdown contents:
  - List of apps (icon, name, window count), sorted by window count descending.
  - Divider
  - "Undo last tile"
  - "Settings…"
  - "Quit"
- **Settings window** (small, SwiftUI):
  - Hotkeys: tile frontmost, undo
  - Gap size slider
  - Target screen: "Screen under mouse" / "Tile per screen"
  - Include minimized windows (toggle)
  - Launch at login (toggle, via `SMAppService`)
- **First-run onboarding:** if Accessibility permission isn't granted, show one window explaining why it's needed, with a button that triggers the system prompt and opens the right System Settings pane. Detect when permission is granted (poll every 1 s) and close the window automatically.

## 5. Tech stack

- Swift 5.9+, SwiftUI + AppKit where needed, **macOS 14 Sonoma minimum**.
- Window control: **Accessibility API** (`AXUIElement`), using `kAXWindowsAttribute`, `kAXPositionAttribute`, `kAXSizeAttribute`, `kAXSubroleAttribute`, `kAXMinimizedAttribute`.
- Running apps: `NSWorkspace.shared.runningApplications`, filtered to `.regular` activation policy.
- Global hotkeys: the [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts) Swift package. It includes a ready-made recorder view for Settings.
- Launch at login: `SMAppService.mainApp`.
- **Not sandboxed.** This is a personal build, which keeps Accessibility simple.
- No third-party dependencies beyond KeyboardShortcuts.

## 6. Suggested structure

```
Spread/
  SpreadApp.swift            // @main, MenuBarExtra, settings scene
  Permissions.swift          // AXIsProcessTrusted check + prompt + polling
  WindowService.swift        // enumerate apps/windows via AX, read/write frames
  GridLayout.swift           // pure function: (n, rect, gap, aspect) -> [CGRect]
  Tiler.swift                // orchestrates: pick windows, order, apply, store undo
  UndoStore.swift            // last arrangement: [AXUIElement: CGRect]
  CoordinateSpace.swift      // NSScreen (bottom-left) <-> AX (top-left) conversion
  Settings/SettingsView.swift
  Onboarding/OnboardingView.swift
SpreadTests/
  GridLayoutTests.swift      // n = 1…12, normal + ultrawide + gap edge cases
```

`GridLayout` must be a **pure function with unit tests**. It's the only part with real logic, and it's fully testable without permissions.

## 7. Milestones

1. **M1 — Engine, no UI.** Permission check + `WindowService` + `GridLayout` + `Tiler`. Hotkey tiles the frontmost app. Verify on Finder, Chrome, VS Code and TextEdit.
2. **M2 — Menu bar.** App list with icons and counts; click to tile.
3. **M3 — Undo + settings.** Undo store, gap slider, screen mode, minimized toggle, launch at login.
4. **M4 — Polish.** Onboarding window, multi-monitor testing, edge cases from §3.
5. **v2 (optional) — Watch mode.** Per-app toggle: an `AXObserver` listens for window created/destroyed and re-tiles automatically.

## 8. Technical notes for Claude Code to verify

These come from general knowledge of macOS, not something tested in this project. **Confirm each one before relying on it.**

- **Coordinate systems:** AX positions use a top-left origin relative to the primary display, while `NSScreen` frames use a bottom-left origin. Getting this conversion wrong breaks multi-monitor setups. Write `CoordinateSpace` first and test it on two screens.
- **Set position → size → position:** some apps (reportedly Electron/Chromium-based ones) apply size and position inconsistently. Rectangle is said to work around this by setting position, then size, then position again. Test with Chrome and VS Code.
- **Accessibility permission resets on rebuild:** macOS ties the permission to the app's code signature. Ad-hoc signed debug builds may lose the permission after every rebuild. Fix: sign with a stable **Apple Development** certificate (a free Apple ID in Xcode works) and build to a fixed location.
- **Spaces:** `kAXWindowsAttribute` is expected to return only windows on the current Space. v1 accepts this limitation and doesn't try to pull windows from other Spaces.
- **Window animations:** some apps animate resizes. Read the frame back after a short delay (~50 ms) if the first read-back doesn't match.

## 9. Acceptance criteria (v1 is done when…)

- [ ] With 5 Chrome windows open, one click on "Google Chrome" in the menu produces a 3 + 2 grid (bottom row wider), 8 px gaps, menu bar and Dock uncovered.
- [ ] The hotkey tiles the frontmost app, with no menu interaction.
- [ ] Undo restores every window to its exact previous frame.
- [ ] Sheets, dialogs, minimized and full-screen windows are never moved (minimized ones are included only when the toggle is on).
- [ ] Works on a two-monitor setup in both screen modes.
- [ ] On first launch without permission, the onboarding window appears and closes by itself once permission is granted.
- [ ] `GridLayoutTests` pass for n = 1…12 on normal and ultrawide aspect ratios.
- [ ] No Dock icon, no network access, CPU idle at ~0% when not tiling.

## 10. Out of scope

Saved layouts and workspaces, snapping by dragging, per-window shortcuts (halves/quarters), gestures, an App Store build, auto-updates.