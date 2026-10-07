import ApplicationServices
import CoreGraphics

/// The arrangement before the last tile. Single level: a new tile replaces it, undo clears it.
final class UndoStore {
    struct Entry {
        let element: AXUIElement
        let pid: pid_t
        let frame: CGRect
        let wasMinimized: Bool
    }

    private(set) var entries: [Entry] = []

    var canUndo: Bool { !entries.isEmpty }

    func record(_ windows: [AppWindow]) {
        entries = windows.map {
            Entry(element: $0.element, pid: $0.pid, frame: $0.frame, wasMinimized: $0.isMinimized)
        }
    }

    /// Returns the stored arrangement and clears the store.
    func take() -> [Entry] {
        defer { entries = [] }
        return entries
    }
}
