import AppKit

/// Fires when a modifier combination is pressed and released on its own, e.g. a tap of ⌃⌥⌘.
///
/// Any other key, an extra modifier or a mouse click while the combination is held cancels the tap,
/// so app shortcuts like ⌃⌥⌘T and ⌃⌥⌘-click keep working. Global monitors need Accessibility access.
final class ModifierTap {
    private let modifiers: NSEvent.ModifierFlags
    private let action: () -> Void
    private var monitors: [Any] = []
    private var state = State.idle

    nonisolated enum State {
        case idle
        /// The full combination is (or was) held and nothing else happened yet.
        case armed
        /// Something else happened while keys were held; ignore until everything is released.
        case cancelled
    }

    /// Flags that say nothing about which modifier keys are held.
    private static let ignoredFlags: NSEvent.ModifierFlags = [.capsLock, .numericPad, .function, .help]

    private static let cancellingEvents: NSEvent.EventTypeMask = [
        .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
    ]

    init(_ modifiers: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.modifiers = modifiers
        self.action = action
    }

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        // Global monitors see other apps' events, local ones our own (e.g. the Settings window).
        // Both deliver on the main thread.
        let handle: (NSEvent) -> Void = { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let mask: NSEvent.EventTypeMask = Self.cancellingEvents.union(.flagsChanged)
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handle) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    /// Treat the current press as something else (e.g. a hotkey that swallowed its key event).
    func cancel() {
        if state != .idle { state = .cancelled }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        state = .idle
    }

    private func handle(_ event: NSEvent) {
        let held: NSEvent.ModifierFlags? = event.type == .flagsChanged
            ? event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(Self.ignoredFlags)
            : nil
        let (state, fire) = Self.step(state, held: held, combination: modifiers)
        self.state = state
        if fire { action() }
    }

    /// One state transition. `held` is the set of modifiers after a flags change, or nil for any
    /// other event (key, click, scroll), which cancels the tap.
    nonisolated static func step(
        _ state: State, held: NSEvent.ModifierFlags?, combination: NSEvent.ModifierFlags
    ) -> (state: State, fire: Bool) {
        // Fire once every key of the combination is released.
        if held?.isEmpty == true { return (.idle, state == .armed) }
        guard let held else { return (state == .idle ? .idle : .cancelled, false) }
        switch state {
        case .cancelled:
            return (.cancelled, false)
        case .idle, .armed:
            if held == combination { return (.armed, false) }
            // Keys pressed on the way in, or released one by one on the way out: keep waiting.
            if held.isSubset(of: combination) { return (state, false) }
            // Another modifier joined in (e.g. ⇧): this is a different shortcut.
            return (.cancelled, false)
        }
    }
}
