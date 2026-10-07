import Foundation
import Observation
import ServiceManagement

@Observable
final class SettingsStore {
    /// Where a tile puts the windows. Persisted as "underMouse", "perScreen" or "display:<uuid>".
    enum ScreenTarget: Hashable {
        /// All windows gather on the screen under the pointer.
        case underMouse
        /// All windows gather on one specific display.
        case display(id: String)
        /// Each screen tiles the windows already on it; nothing crosses displays.
        case perScreen
        /// Windows are shared out across every display in proportion to its size.
        case allScreens

        var rawValue: String {
            switch self {
            case .underMouse: "underMouse"
            case .perScreen: "perScreen"
            case .allScreens: "allScreens"
            case .display(let id): "display:\(id)"
            }
        }

        init?(rawValue: String) {
            switch rawValue {
            case "underMouse": self = .underMouse
            case "perScreen": self = .perScreen
            case "allScreens": self = .allScreens
            case let value where value.hasPrefix("display:"):
                self = .display(id: String(value.dropFirst("display:".count)))
            default: return nil
            }
        }

        /// A chosen display that is not connected right now falls back to the screen under the mouse.
        /// The choice itself is kept, so it applies again once the display is back.
        var resolved: ScreenTarget {
            if case .display(let id) = self, Display.with(id: id) == nil { return .underMouse }
            return self
        }
    }

    private enum Key {
        static let gap = "gap"
        static let screenMode = "screenMode"
        static let includeMinimized = "includeMinimized"
        static let targetCellAspect = "targetCellAspect"
        static let modifierTap = "modifierTap"
    }

    static let gapRange: ClosedRange<Double> = 0...24

    @ObservationIgnored private let defaults: UserDefaults

    var gap: Double {
        didSet { defaults.set(gap, forKey: Key.gap) }
    }

    var screenTarget: ScreenTarget {
        didSet { defaults.set(screenTarget.rawValue, forKey: Key.screenMode) }
    }

    var includeMinimized: Bool {
        didSet { defaults.set(includeMinimized, forKey: Key.includeMinimized) }
    }

    /// Tapping ⌃⌥⌘ on their own tiles the frontmost app onto the screen under the mouse.
    var modifierTapEnabled: Bool {
        didSet { defaults.set(modifierTapEnabled, forKey: Key.modifierTap) }
    }

    private(set) var launchAtLogin: Bool
    private(set) var launchAtLoginError: String?

    /// Hidden tunable for the grid shape: `defaults write design.uprive.spread targetCellAspect -float 1.4`.
    var targetCellAspect: CGFloat {
        let value = defaults.double(forKey: Key.targetCellAspect)
        return value > 0 ? value : GridLayout.defaultTargetCellAspect
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedGap = defaults.object(forKey: Key.gap) as? Double ?? 8
        gap = min(max(storedGap, Self.gapRange.lowerBound), Self.gapRange.upperBound)
        screenTarget = defaults.string(forKey: Key.screenMode).flatMap(ScreenTarget.init(rawValue:)) ?? .underMouse
        includeMinimized = defaults.bool(forKey: Key.includeMinimized)
        modifierTapEnabled = defaults.object(forKey: Key.modifierTap) as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginError = "Allow Spread in System Settings › General › Login Items."
        }
    }
}
