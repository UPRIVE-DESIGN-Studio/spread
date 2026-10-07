import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let tileFrontmost = Self("tileFrontmost", initial: .init(.t, modifiers: [.control, .option]))
    static let tileAllScreens = Self("tileAllScreens", initial: .init(.a, modifiers: [.control, .option, .command]))
    static let undoTile = Self("undoTile", initial: .init(.z, modifiers: [.control, .option]))
}

enum Hotkeys {
    /// `onAnyKeyDown` runs when any Spread hotkey goes down. Registered hotkeys swallow their key
    /// event, so the ⌃⌥⌘ tap detector never sees the "A" of ⌃⌥⌘A and must be told to stand down.
    static func register(tiler: Tiler, onAnyKeyDown: @escaping () -> Void) {
        for name in [KeyboardShortcuts.Name.tileFrontmost, .tileAllScreens, .undoTile] {
            KeyboardShortcuts.onKeyDown(for: name) { onAnyKeyDown() }
        }
        KeyboardShortcuts.onKeyUp(for: .tileFrontmost) { tiler.tileFrontmost() }
        KeyboardShortcuts.onKeyUp(for: .tileAllScreens) { tiler.tileFrontmost(onto: .allScreens) }
        KeyboardShortcuts.onKeyUp(for: .undoTile) { tiler.undo() }
    }
}
