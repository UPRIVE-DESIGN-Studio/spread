# Plan: "Spread" macOS menu bar window tiler

## Context

`SPEC.md` describes a personal menu bar utility that tiles all windows of one app into an even grid (menu click, global hotkey, undo). The folder contains only the spec; nothing is built yet and it is not a git repo.

**Stack decision: native Swift (SwiftUI + AppKit), as the spec already assumes.** React Native for macOS is the wrong tool here: every core capability is a native-only API (`AXUIElement` window control, `NSStatusItem`/`NSMenu`, `NSScreen`, global hotkeys, `SMAppService`). A React Native build would be a thin JS shell over hand-written native modules for everything, with no upside for a no-network, no-UI-heavy app. Native also leaves the "make it really nice later" path open (SwiftUI, Liquid Glass materials on macOS 26, Instruments).

Decisions confirmed with the user:
- **Grid rule:** aspect-aware column selection (matches all spec examples), not the literal `ceil(sqrt(n))`.
- **Project tooling:** XcodeGen (`project.yml` is the source of truth; `.xcodeproj` generated and git-ignored).
- **Name / bundle ID:** `Spread` / `design.uprive.spread`.

Environment facts (checked):
- macOS 26.5.1, Xcode 26.3, Swift 6.2.4. Deployment target stays macOS 14 per spec.
- Signing identity available: `Apple Development: Created via API (XSLG72G6JY)`, team **AWK5ZJPJG6**, valid until 2027‑07‑28. Manual signing with it needs no provisioning profile (no restricted entitlements, not sandboxed) and keeps the Accessibility grant stable across rebuilds (TCC keys on team ID + bundle ID).
- Homebrew present; `xcodegen` 2.46.0 not yet installed.
- KeyboardShortcuts latest release: 3.1.0 (macOS 10.15+, works while an NSMenu is open, no permission dialogs).
- Rectangle (reference implementation) confirms spec §8: it sets **size → position → size** and temporarily disables the app's `AXEnhancedUserInterface` attribute while moving; it uses `AXUIElementSetMessagingTimeout` to avoid hangs.

## Architecture decisions (deviations from spec §6 explained)

1. **Menu bar via AppKit `NSStatusItem` + `NSMenu`, not SwiftUI `MenuBarExtra`.** The app list must be rebuilt every time the menu opens (window counts change constantly) and show real app icons. `NSMenuDelegate.menuNeedsUpdate(_:)` gives exactly that; `MenuBarExtra(.menu)` content refresh on open is unreliable. SwiftUI is still used for the Settings and Onboarding content, hosted in `NSWindow` via `NSHostingController` (own windows, so no dependency on the private `showSettingsWindow:` selector).
2. **Entry point is `@main final class AppDelegate: NSObject, NSApplicationDelegate`** (no main nib, no SwiftUI `App` scene). Cleanest for an `LSUIElement` app.
3. **All engine geometry lives in AX coordinates** (top-left origin, relative to the primary display). `CoordinateSpace` converts each `NSScreen.visibleFrame` into AX space once; windows are never converted back.
4. **Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** (Xcode 26 "approachable concurrency"). Everything AX-related runs on the main actor, so `AXUIElement` (non-Sendable) never crosses isolation. Fallback if it fights us: `SWIFT_VERSION = 5`.
5. **Tests use Swift Testing** (`import Testing`, parameterized `@Test(arguments: 1...12)`).
6. **Screen modes interpretation** (spec §3 is ambiguous): *Screen under mouse* (default) gathers **all** of the app's tileable windows on the current Space onto the screen under the pointer. *Tile per screen* groups windows by the screen they are on and tiles each group in place, so nothing crosses displays. This reading follows the spec's own "so no window moves between displays" contrast.

## File layout

```
distri-boot/
  project.yml                 # XcodeGen definition (targets, SPM dep, Info.plist keys, signing)
  Makefile                    # gen / build / test / run / install shortcuts
  .gitignore                  # *.xcodeproj, DerivedData, .build, xcuserdata, .DS_Store
  SPEC.md
  Spread/
    AppDelegate.swift         # @main; wires everything, shows onboarding if not trusted
    Permissions.swift         # AXIsProcessTrusted, prompt, open Settings pane
    Hotkeys.swift             # KeyboardShortcuts.Name defs + registration
    Engine/
      CoordinateSpace.swift   # Cocoa <-> AX rect conversion, screen lookup
      GridLayout.swift        # pure: frames(count:in:gap:targetCellAspect:) -> [CGRect]
      WindowService.swift     # AX enumeration, tileable filter, read/write frames
      Tiler.swift             # orchestration: pick windows, group by screen, order, apply, record undo
      UndoStore.swift         # last arrangement [(AXUIElement, CGRect, wasMinimized)]
    Settings/
      SettingsStore.swift     # @Observable, UserDefaults-backed; launch-at-login via SMAppService
      SettingsView.swift      # SwiftUI form
    Onboarding/
      OnboardingView.swift    # permission explainer, polls every 1 s
    UI/
      StatusMenuController.swift  # NSStatusItem + NSMenu + menuNeedsUpdate
      WindowHost.swift            # show a SwiftUI view in an NSWindow, activate app, reuse window
    Resources/Assets.xcassets      # AppIcon placeholder (menu bar icon is an SF Symbol, no asset)
  SpreadTests/
    GridLayoutTests.swift
    CoordinateSpaceTests.swift
```

## Component details

### project.yml (key settings)
- `options`: `deploymentTarget.macOS: "14.0"`, `bundleIdPrefix: design.uprive`.
- `packages.KeyboardShortcuts`: `https://github.com/sindresorhus/KeyboardShortcuts`, `from: 3.1.0`.
- Base settings: `SWIFT_VERSION: 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY: YES`, `DEVELOPMENT_TEAM: AWK5ZJPJG6`, `CODE_SIGN_STYLE: Manual`, `CODE_SIGN_IDENTITY: "Apple Development"`, `ENABLE_APP_SANDBOX: NO`, `ENABLE_HARDENED_RUNTIME: YES`.
- Target `Spread` (application, macOS): `PRODUCT_BUNDLE_IDENTIFIER: design.uprive.spread`; Info.plist generated with `LSUIElement: true`, `CFBundleDisplayName: Spread`; explicit `scheme` with `testTargets: [SpreadTests]`.
- Target `SpreadTests` (bundle.unit-test) depending on `Spread`.

### GridLayout (pure, tested)
Signature: `static func frames(count n: Int, in bounds: CGRect, gap: CGFloat, targetCellAspect: CGFloat = 1.2) -> [CGRect]`.
- `n <= 0` → `[]`.
- For each candidate `cols in 1...n`: `rows = ceil(n / cols)`, full rows hold `cols`, last row holds `n - cols*(rows-1)` windows and **widens to fill the row** (spec). Cell height `(H - gap*(rows+1)) / rows`; width in a row with `k` cells `(W - gap*(k+1)) / k`.
- Score each candidate by `max over rows |ln(cellAspect / targetCellAspect)|` (log ratio so too-wide and too-tall count equally; the max punishes a single stretched last-row cell). Pick the minimum; tie → fewer rows.
- Checked by hand for 16:9: 1 full, 2 side by side, 3 three columns, 4 → 2×2, 5 → 3+2, 6 → 3×2, 7 → 4+3, 8 → 4×2, 9 → 3×3, 10 → 5×2, 11 → 4+4+3, 12 → 4×3. Portrait 9:16 with 3 → stacked. Ultrawide 21:9 with 3 → three columns, with 4 → 2×2 (becomes 4 columns on 32:9). `targetCellAspect` is the single tunable; expose it as a hidden `UserDefaults` key (`targetCellAspect`), not in the UI.
- Output in reading order (row by row, left to right), rounded to whole points.

### CoordinateSpace
- Pure core: `axRect(_ cocoa: CGRect, primaryHeight: CGFloat) -> CGRect` with `y' = primaryHeight - cocoa.maxY`, and the inverse. `primaryHeight` comes from `NSScreen.screens[0].frame.height` (index 0 is always the display whose Cocoa origin is (0,0), which is the AX origin; `NSScreen.main` is the focused screen and must not be used).
- `screenUnderMouse()`: `NSEvent.mouseLocation` against `NSScreen.screens` frames, fallback `.main`.
- `screen(containingAX frame:)`: largest intersection area with each screen's frame, fallback the one containing the center, fallback primary.

### WindowService (AX)
- Apps: `NSWorkspace.shared.runningApplications` filtered to `.regular`, not terminated.
- Per app: `AXUIElementCreateApplication(pid)`, `AXUIElementSetMessagingTimeout(app, 0.25)` (so one hung app cannot stall the menu), read `kAXWindowsAttribute`.
- Tileable filter: role `AXWindow`, subrole `AXStandardWindow`; `kAXMinimizedAttribute == false` unless the include-minimized setting is on; skip when the `"AXFullScreen"` attribute reads true (private but universally used; fallback: frame equals a screen's full `frame`).
- Read frame: `kAXPositionAttribute` / `kAXSizeAttribute` via `AXValueGetValue(.cgPoint / .cgSize)`.
- `apply(_ assignments: [(window, frame)])`: read the app element's `AXEnhancedUserInterface`; if true set it false for the duration and restore at the end. For each window set **size → position → size**. Then read all frames back once; for any mismatch (>1 pt) wait ~50 ms and read again; if still off, set position only so the top-left stays in its cell and the window overflows (spec: "don't fight it in a loop"). Minimized windows included by setting are unminimized first (`kAXMinimizedAttribute = false`).

### Tiler
- `tile(app:)`: windows → group by mode (§Architecture 6) → per group: `bounds = axRect(screen.visibleFrame)`, `frames = GridLayout.frames(...)`, order windows by current center in reading order (band index by `centerY` over the row count, then `centerX`), record undo snapshot, apply.
- `tileFrontmost()`: `NSWorkspace.shared.frontmostApplication`, ignore if nil or ourselves.
- `undo()`: restore every stored frame (and re-minimize windows that were unminimized); stale elements fail silently; store cleared afterwards (single level, per spec).

### Hotkeys
```swift
extension KeyboardShortcuts.Name {
    static let tileFrontmost = Self("tileFrontmost", initial: .init(.t, modifiers: [.control, .option]))
    static let undoTile      = Self("undoTile",      initial: .init(.z, modifiers: [.control, .option]))
}
```
Registered with `KeyboardShortcuts.onKeyUp(for:)` in `AppDelegate`. (Label is `initial:` in the 3.x README; confirm against the resolved package, older versions used `default:`.) Use `NSMenuItem.setShortcut(for: .undoTile)` so the menu shows the live hotkey.

### StatusMenuController
- Template SF Symbol icon (`rectangle.split.3x3`) on the status button.
- `menuNeedsUpdate`: if not trusted → single "Grant Accessibility Access…" item. Otherwise one item per app with ≥1 tileable window: title `"Google Chrome (5)"`, `image = app.icon` at 16×16, `representedObject = pid`, sorted by count desc then name; empty state "No tileable windows" (disabled). Then separator, "Undo Last Tile" (enabled iff undo available), "Settings…" (⌘,), "Quit Spread" (⌘Q).

### Permissions + Onboarding
- `AXIsProcessTrusted()`; prompt via `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`; open pane via `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- Onboarding window shown at launch when untrusted; a 1 s `Timer` polls and closes the window on grant. Menu still works meanwhile (shows the grant item).

### Settings
- `SettingsStore` (`@Observable`): `gap` (0…24, default 8), `screenMode` (`.underMouse` / `.perScreen`), `includeMinimized` (false), `launchAtLogin` (reads `SMAppService.mainApp.status == .enabled`, setter calls `register()` / `unregister()`, surfaces errors inline).
- `SettingsView`: grouped `Form` with two `KeyboardShortcuts.Recorder`s, gap `Slider` with value label, screen-mode `Picker`, two `Toggle`s. Fixed ~420×360 window.

### WindowHost
Small helper owning one `NSWindow` per view (settings, onboarding): `NSHostingController`, `isReleasedWhenClosed = false`, `center()`, `makeKeyAndOrderFront`, `NSApp.activate(ignoringOtherApps: true)`; re-shows the existing window if already open.

### Makefile targets
`gen` (xcodegen generate), `build`, `test`, `run` (build + open the Debug app from DerivedData), `install` (Release build copied to `/Applications/Spread.app`, so launch-at-login has a stable path).

## Implementation order (maps to spec milestones)

0. **Setup**: `brew install xcodegen`; `git init`; write `project.yml`, `.gitignore`, `Makefile`, empty `AppDelegate`; generate; confirm an empty `LSUIElement` app builds and signs with the Apple Development identity. (No commits unless asked.)
1. **M1 Engine**: `CoordinateSpace` + tests → `GridLayout` + tests → `WindowService` → `UndoStore` → `Tiler` → `Permissions` (prompt only) → `Hotkeys`. Hotkey tiles the frontmost app. Manually verify on Finder, Chrome, VS Code, TextEdit.
2. **M2 Menu bar**: `StatusMenuController` with live app list; click to tile; Quit.
3. **M3 Undo + Settings**: undo menu item + hotkey, `SettingsStore`, `SettingsView`, launch at login, `WindowHost`.
4. **M4 Polish**: `OnboardingView` with polling, two-monitor pass in both modes, min-size overflow rule, animated-resize read-back, include-minimized path.

## Verification

Automated (`make test` / `xcodebuild test -scheme Spread -destination 'platform=macOS'`):
- `GridLayoutTests`: for n = 1…12 × aspects {16:9, 21:9, 32:9, 9:16} × gaps {0, 8, 24}: frame count == n, every frame inside `bounds` inset by `gap`, no two frames overlap, each row spans the full width, all heights equal, frames in reading order. Pinned shapes on 16:9: 1 full, 2 side by side, 3 three columns, 4 → 2×2, 5 → 3+2 with wider bottom row, 6 → 3×2. Pinned on 9:16: 3 stacked. `n = 0` → empty.
- `CoordinateSpaceTests`: round trip with a simulated two-display layout (primary 1920×1080 at origin, secondary 2560×1440 at (1920, 200)); negative AX y for the taller secondary.

Manual (spec §9 acceptance list), done after each milestone:
- 5 Chrome windows → menu click → 3+2 grid, 8 px gaps, menu bar and Dock uncovered.
- `⌃⌥T` tiles the frontmost app; `⌃⌥Z` restores exact frames (compare read-back frames before/after).
- Open a sheet, a dialog, a minimized and a full-screen window: none move; minimized moves only with the toggle on.
- Two monitors: both screen modes; a window with its center on display 2 stays there in per-screen mode.
- Launch without permission → onboarding appears → grant → window closes by itself within ~1 s; rebuild and relaunch → permission still granted (signing check).
- No Dock icon; Activity Monitor shows ~0% CPU idle; `nettop`/no network entitlement.
- Idle check that menu opening stays snappy with ~20 running apps (messaging timeout).

## Risks to confirm during implementation
- KeyboardShortcuts 3.1.0 `Name` initializer label (`initial:` vs `default:`).
- `"AXFullScreen"` attribute present on Sonoma+ windows (fallback is frame == screen frame).
- `kAXWindowsAttribute` returns only current-Space windows; if a test shows off-Space windows moving, add an on-screen cross-check via `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` matched by pid + frame.
- Swift 6 strict concurrency friction with CF/AX types → fall back to Swift 5 language mode.
- Chrome/Electron min-size enforcement → overflow rule covers it; verify with a 3×4 layout of small cells.
