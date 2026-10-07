import AppKit

/// Converts between Cocoa screen coordinates (bottom-left origin) and Accessibility
/// coordinates (top-left origin of the primary display, y grows downwards).
///
/// All tiling geometry lives in AX space. Screen frames are converted once, windows never.
enum CoordinateSpace {
    // MARK: Pure core

    /// Cocoa rect → AX rect. `primaryHeight` is the height of the display whose Cocoa origin is (0, 0).
    nonisolated static func axRect(_ cocoa: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX, y: primaryHeight - cocoa.maxY, width: cocoa.width, height: cocoa.height)
    }

    /// AX rect → Cocoa rect. The flip is its own inverse.
    nonisolated static func cocoaRect(_ ax: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: ax.minX, y: primaryHeight - ax.maxY, width: ax.width, height: ax.height)
    }

    /// Index of the screen a window belongs to: the largest overlap wins, then the screen
    /// containing the window's center. Returns nil only when `screens` is empty.
    nonisolated static func bestScreenIndex(for frame: CGRect, among screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > 0, area > (best?.area ?? 0) { best = (index, area) }
        }
        if let best { return best.index }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.firstIndex { $0.contains(center) } ?? 0
    }

    // MARK: NSScreen helpers

    /// `NSScreen.screens[0]` is always the display at the Cocoa origin, which is the AX origin.
    /// (`NSScreen.main` is the focused screen and must not be used here.)
    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func axFrame(of screen: NSScreen) -> CGRect {
        axRect(screen.frame, primaryHeight: primaryHeight)
    }

    static func axVisibleFrame(of screen: NSScreen) -> CGRect {
        axRect(screen.visibleFrame, primaryHeight: primaryHeight)
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// The screen an AX-space window frame is mostly on, falling back to the primary display.
    static func screen(containingAX frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        guard let index = bestScreenIndex(for: frame, among: screens.map(axFrame(of:))) else { return nil }
        return screens[index]
    }
}

/// A connected display with a stable identity and a menu-friendly name.
struct Display {
    /// Display UUID: survives reboots and reconnects, unlike `CGDirectDisplayID`.
    let id: String
    let name: String
    let screen: NSScreen

    /// Connected displays left to right. Identical models get a position suffix ("DELL U2723QE 2").
    static func all() -> [Display] {
        let screens = NSScreen.screens
            .compactMap { screen in screen.displayUUID.map { (id: $0, screen: screen) } }
            .sorted { $0.screen.frame.minX < $1.screen.frame.minX }
        var seen: [String: Int] = [:]
        let totals = Dictionary(grouping: screens, by: \.screen.localizedName).mapValues(\.count)
        return screens.map { entry in
            let base = entry.screen.localizedName
            var name = base
            if totals[base, default: 0] > 1 {
                seen[base, default: 0] += 1
                name = "\(base) \(seen[base]!)"
            }
            return Display(id: entry.id, name: name, screen: entry.screen)
        }
    }

    static func with(id: String) -> Display? {
        all().first { $0.id == id }
    }
}

extension NSScreen {
    var displayUUID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
