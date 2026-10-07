import AppKit

/// Orchestrates a tile: pick windows, group them by target screen, order, apply, remember undo.
final class Tiler {
    private let settings: SettingsStore
    let undoStore = UndoStore()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    /// `target` overrides the saved screen target for this one tile.
    func tileFrontmost(onto target: SettingsStore.ScreenTarget? = nil) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        tile(pid: app.processIdentifier, onto: target)
    }

    func tile(pid: pid_t, onto target: SettingsStore.ScreenTarget? = nil) {
        guard Permissions.isTrusted else { return }
        let windows = WindowService.tileableWindows(pid: pid, includeMinimized: settings.includeMinimized)
        guard !windows.isEmpty else { return }

        var assignments: [FrameAssignment] = []
        for (screen, group) in groups(for: windows, target: target ?? settings.screenTarget) {
            let bounds = CoordinateSpace.axVisibleFrame(of: screen)
            let gap = CGFloat(settings.gap)
            let aspect = settings.targetCellAspect
            let rows = GridLayout.rowCounts(count: group.count, in: bounds, gap: gap, targetCellAspect: aspect).count
            let frames = GridLayout.frames(count: group.count, in: bounds, gap: gap, targetCellAspect: aspect)
            let ordered = Self.readingOrder(group, in: bounds, rows: rows)
            assignments += zip(ordered, frames).map { FrameAssignment(window: $0, frame: $1) }
        }

        undoStore.record(windows)
        WindowService.apply(assignments)
    }

    func undo() {
        WindowService.restore(undoStore.take())
    }

    /// Under-mouse and display targets gather everything onto one screen. Per-screen mode tiles
    /// each display's windows in place, so nothing crosses displays. All-screens mode shares the
    /// windows out across every display.
    private func groups(for windows: [AppWindow], target: SettingsStore.ScreenTarget) -> [(NSScreen, [AppWindow])] {
        switch target.resolved {
        case .underMouse:
            guard let screen = CoordinateSpace.screenUnderMouse() else { return [] }
            return [(screen, windows)]
        case .display(let id):
            guard let display = Display.with(id: id) else { return [] }
            return [(display.screen, windows)]
        case .perScreen:
            var groups: [(NSScreen, [AppWindow])] = []
            for window in windows {
                guard let screen = CoordinateSpace.screen(containingAX: window.frame) else { continue }
                if let index = groups.firstIndex(where: { $0.0 == screen }) {
                    groups[index].1.append(window)
                } else {
                    groups.append((screen, [window]))
                }
            }
            return groups
        case .allScreens:
            return spreadAcrossScreens(windows)
        }
    }

    /// Each screen gets a share proportional to its usable area. Screens and windows are both
    /// ordered along the axis the displays are arranged on (left to right, or top to bottom), and
    /// windows are dealt out in that order, so each one lands on or near the screen it is on now.
    private func spreadAcrossScreens(_ windows: [AppWindow]) -> [(NSScreen, [AppWindow])] {
        let screens = NSScreen.screens.map { (screen: $0, bounds: CoordinateSpace.axVisibleFrame(of: $0)) }
        guard screens.count > 1 else {
            return screens.first.map { [($0.screen, windows)] } ?? []
        }

        let xs = screens.map(\.bounds.midX)
        let ys = screens.map(\.bounds.midY)
        let horizontal = (xs.max()! - xs.min()!) >= (ys.max()! - ys.min()!)
        func key(_ rect: CGRect) -> (CGFloat, CGFloat) {
            horizontal ? (rect.midX, rect.midY) : (rect.midY, rect.midX)
        }

        let orderedScreens = screens.sorted { key($0.bounds) < key($1.bounds) }
        let orderedWindows = windows.sorted { key($0.frame) < key($1.frame) }
        let counts = GridLayout.split(
            count: windows.count,
            weights: orderedScreens.map { $0.bounds.width * $0.bounds.height }
        )

        var groups: [(NSScreen, [AppWindow])] = []
        var start = 0
        for (entry, count) in zip(orderedScreens, counts) where count > 0 {
            groups.append((entry.screen, Array(orderedWindows[start..<start + count])))
            start += count
        }
        return groups
    }

    /// Sort windows by their current centers: horizontal bands matching the grid's rows,
    /// then left to right, so each window moves a short, predictable distance.
    private static func readingOrder(_ windows: [AppWindow], in bounds: CGRect, rows: Int) -> [AppWindow] {
        let bandHeight = bounds.height / CGFloat(max(rows, 1))
        func band(_ window: AppWindow) -> Int {
            let offset = window.frame.midY - bounds.minY
            return min(max(Int((offset / bandHeight).rounded(.down)), 0), max(rows - 1, 0))
        }
        return windows.sorted {
            let (a, b) = (band($0), band($1))
            return a != b ? a < b : $0.frame.midX < $1.frame.midX
        }
    }
}
