import AppKit
import ApplicationServices

/// One window of one app, as seen through the Accessibility API. Frames are in AX coordinates.
struct AppWindow {
    let element: AXUIElement
    let pid: pid_t
    let frame: CGRect
    let isMinimized: Bool
}

/// A frame to write to a window. `unminimize` restores minimized windows before moving them.
struct FrameAssignment {
    let window: AppWindow
    let frame: CGRect
    var unminimize: Bool { window.isMinimized }
}

enum WindowService {
    /// Short enough that one hung app cannot stall the menu.
    private static let enumerationTimeout: Float = 0.25
    /// Writes can legitimately take longer (Chromium, Electron).
    private static let writeTimeout: Float = 1.0
    /// Read-back tolerance in points.
    private static let tolerance: CGFloat = 1

    // MARK: Enumeration

    /// Regular (Dock) apps that are still running, excluding Spread itself.
    static func candidateApps() -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != ownPID
        }
    }

    /// Standard windows of `pid` on the current Space that may be tiled.
    static func tileableWindows(pid: pid_t, includeMinimized: Bool) -> [AppWindow] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, enumerationTimeout)
        guard let windows: [AXUIElement] = app.value(of: kAXWindowsAttribute) else { return [] }

        let screenFrames = NSScreen.screens.map(CoordinateSpace.axFrame(of:))
        return windows.compactMap { element in
            AXUIElementSetMessagingTimeout(element, enumerationTimeout)
            guard element.string(of: kAXRoleAttribute) == kAXWindowRole,
                  element.string(of: kAXSubroleAttribute) == kAXStandardWindowSubrole,
                  let frame = element.frame
            else { return nil }

            let minimized = element.bool(of: kAXMinimizedAttribute) ?? false
            if minimized && !includeMinimized { return nil }
            if isFullScreen(element, frame: frame, minimized: minimized, screens: screenFrames) { return nil }
            return AppWindow(element: element, pid: pid, frame: frame, isMinimized: minimized)
        }
    }

    /// "AXFullScreen" is not a public constant but every window manager relies on it.
    /// Fallback for apps that don't expose it: a non-minimized window exactly covering a screen.
    private static func isFullScreen(
        _ element: AXUIElement, frame: CGRect, minimized: Bool, screens: [CGRect]
    ) -> Bool {
        if let fullScreen = element.bool(of: "AXFullScreen") { return fullScreen }
        return !minimized && screens.contains { $0.equalTo(frame) }
    }

    // MARK: Writing

    /// Moves every window into its frame. Sets size → position → size (some apps clamp the
    /// position against the old size), then reads back once, waits ~50 ms for animating apps,
    /// and for windows that still refuse (minimum sizes) just pins the top-left corner.
    static func apply(_ assignments: [FrameAssignment]) {
        guard !assignments.isEmpty else { return }
        withEnhancedUIDisabled(for: Set(assignments.map(\.window.pid))) {
            for assignment in assignments {
                let element = assignment.window.element
                AXUIElementSetMessagingTimeout(element, writeTimeout)
                if assignment.unminimize {
                    element.set(kAXMinimizedAttribute, to: kCFBooleanFalse)
                }
                write(assignment.frame, to: element)
            }

            var mismatched = assignments.filter { !matches($0) }
            guard !mismatched.isEmpty else { return }
            Thread.sleep(forTimeInterval: 0.05)
            mismatched = mismatched.filter { !matches($0) }
            for assignment in mismatched {
                assignment.window.element.setPosition(assignment.frame.origin)
            }
        }
    }

    /// Restores frames exactly and re-minimizes windows that were minimized before.
    static func restore(_ entries: [UndoStore.Entry]) {
        guard !entries.isEmpty else { return }
        withEnhancedUIDisabled(for: Set(entries.map(\.pid))) {
            for entry in entries {
                AXUIElementSetMessagingTimeout(entry.element, writeTimeout)
                write(entry.frame, to: entry.element)
                if entry.wasMinimized {
                    entry.element.set(kAXMinimizedAttribute, to: kCFBooleanTrue)
                }
            }
        }
    }

    private static func write(_ frame: CGRect, to element: AXUIElement) {
        element.setSize(frame.size)
        element.setPosition(frame.origin)
        element.setSize(frame.size)
    }

    private static func matches(_ assignment: FrameAssignment) -> Bool {
        guard let actual = assignment.window.element.frame else { return true } // window gone
        let target = assignment.frame
        return abs(actual.minX - target.minX) <= tolerance
            && abs(actual.minY - target.minY) <= tolerance
            && abs(actual.width - target.width) <= tolerance
            && abs(actual.height - target.height) <= tolerance
    }

    /// `AXEnhancedUserInterface` (turned on by VoiceOver and some utilities) makes apps animate
    /// and misplace programmatic moves. Switch it off for the duration and restore it afterwards.
    private static func withEnhancedUIDisabled(for pids: Set<pid_t>, _ body: () -> Void) {
        let attribute = "AXEnhancedUserInterface"
        var restore: [AXUIElement] = []
        for pid in pids {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, writeTimeout)
            if app.bool(of: attribute) == true {
                app.set(attribute, to: kCFBooleanFalse)
                restore.append(app)
            }
        }
        body()
        for app in restore {
            app.set(attribute, to: kCFBooleanTrue)
        }
    }
}

// MARK: - AXUIElement helpers

extension AXUIElement {
    fileprivate func rawValue(of attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    fileprivate func value(of attribute: String) -> [AXUIElement]? {
        rawValue(of: attribute) as? [AXUIElement]
    }

    fileprivate func string(of attribute: String) -> String? {
        rawValue(of: attribute) as? String
    }

    fileprivate func bool(of attribute: String) -> Bool? {
        rawValue(of: attribute) as? Bool
    }

    fileprivate func axValue(of attribute: String) -> AXValue? {
        guard let value = rawValue(of: attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    var frame: CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(of: kAXPositionAttribute),
              let dimensions = axValue(of: kAXSizeAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(dimensions, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    fileprivate func set(_ attribute: String, to value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(self, attribute as CFString, value) == .success
    }

    fileprivate func setPosition(_ point: CGPoint) {
        var point = point
        if let value = AXValueCreate(.cgPoint, &point) { set(kAXPositionAttribute, to: value) }
    }

    fileprivate func setSize(_ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { set(kAXSizeAttribute, to: value) }
    }
}
