import AppKit
import KeyboardShortcuts

/// The menu bar icon and its dropdown. The app list is rebuilt every time the menu opens,
/// because window counts change constantly.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let tiler: Tiler
    private let settings: SettingsStore
    private let showSettings: () -> Void
    private let showOnboarding: () -> Void

    init(
        tiler: Tiler,
        settings: SettingsStore,
        showSettings: @escaping () -> Void,
        showOnboarding: @escaping () -> Void
    ) {
        self.tiler = tiler
        self.settings = settings
        self.showSettings = showSettings
        self.showOnboarding = showOnboarding
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.split.3x3", accessibilityDescription: "Spread")
            image?.isTemplate = true
            button.image = image
        }
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Permissions.isTrusted {
            addAppItems(to: menu)
        } else {
            menu.addItem(item("Grant Accessibility Access…", action: #selector(grantAccess)))
        }

        menu.addItem(.separator())

        if NSScreen.screens.count > 1 {
            addScreenTargetItems(to: menu)
            menu.addItem(.separator())
        }

        let undo = item("Undo Last Tile", action: #selector(undoLastTile))
        undo.setShortcut(for: .undoTile)
        undo.isEnabled = tiler.undoStore.canUndo
        menu.addItem(undo)

        menu.addItem(item("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(item("Quit Spread", action: #selector(quit), key: "q"))
    }

    private func addAppItems(to menu: NSMenu) {
        var apps: [(app: NSRunningApplication, name: String, count: Int)] = []
        for app in WindowService.candidateApps() {
            let windows = WindowService.tileableWindows(
                pid: app.processIdentifier, includeMinimized: settings.includeMinimized
            )
            guard !windows.isEmpty else { continue }
            apps.append((app, app.localizedName ?? "Unknown", windows.count))
        }
        apps.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        guard !apps.isEmpty else {
            let empty = NSMenuItem(title: "No tileable windows", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for (app, name, count) in apps {
            let entry = item("\(name) (\(count))", action: #selector(tileApp(_:)))
            entry.representedObject = app
            if let icon = app.icon?.copy() as? NSImage {
                icon.size = NSSize(width: 16, height: 16)
                entry.image = icon
            }
            menu.addItem(entry)
        }
    }

    /// "Tile Onto" radio group: screen under mouse, each display by name, or each screen in place.
    private func addScreenTargetItems(to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: "Tile Onto"))
        let current = settings.screenTarget.resolved
        var targets: [(String, SettingsStore.ScreenTarget)] = [("Screen Under Mouse", .underMouse)]
        targets += Display.all().map { ($0.name, .display(id: $0.id)) }
        targets.append(("All Screens", .allScreens))
        targets.append(("Each Screen in Place", .perScreen))

        for (title, target) in targets {
            let entry = item(title, action: #selector(selectScreenTarget(_:)))
            entry.representedObject = target.rawValue
            entry.state = target == current ? .on : .off
            menu.addItem(entry)
        }
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func tileApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? NSRunningApplication else { return }
        tiler.tile(pid: app.processIdentifier)
        // Bring the freshly tiled windows to the front so the grid is visible.
        app.activate(options: [.activateAllWindows])
    }

    @objc private func selectScreenTarget(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let target = SettingsStore.ScreenTarget(rawValue: raw)
        else { return }
        settings.screenTarget = target
    }

    @objc private func undoLastTile() {
        tiler.undo()
    }

    @objc private func grantAccess() {
        showOnboarding()
    }

    @objc private func openSettings() {
        showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
