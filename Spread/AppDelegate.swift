import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var tiler = Tiler(settings: settings)
    private var statusMenu: StatusMenuController?
    private var permissionPoll: Task<Void, Never>?

    /// Tap ⌃⌥⌘: tile the frontmost app onto the screen under the mouse, whatever the saved target.
    private lazy var modifierTap = ModifierTap([.control, .option, .command]) { [weak self] in
        self?.tiler.tileFrontmost(onto: .underMouse)
    }

    private lazy var settingsWindow = WindowHost(title: "Spread Settings") { [settings] in
        SettingsView(settings: settings)
    }

    private lazy var onboardingWindow = WindowHost(title: "Welcome to Spread") {
        OnboardingView()
    }

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside this app; keep the host inert.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        statusMenu = StatusMenuController(
            tiler: tiler,
            settings: settings,
            showSettings: { [weak self] in self?.settingsWindow.show() },
            showOnboarding: { [weak self] in self?.showOnboarding() }
        )
        Hotkeys.register(tiler: tiler) { [weak self] in self?.modifierTap.cancel() }
        observeModifierTapSetting()

        if !Permissions.isTrusted {
            showOnboarding()
        }
    }

    /// Shows the permission explainer and polls once a second until access is granted.
    private func showOnboarding() {
        onboardingWindow.show()
        guard permissionPoll == nil else { return }
        permissionPoll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if Permissions.isTrusted {
                    self.updateModifierTap()
                    self.onboardingWindow.close()
                    self.permissionPoll = nil
                    return
                }
            }
        }
    }

    private func observeModifierTapSetting() {
        withObservationTracking {
            _ = settings.modifierTapEnabled
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeModifierTapSetting() }
        }
        updateModifierTap()
    }

    /// The global monitor only receives events once Accessibility access is granted.
    private func updateModifierTap() {
        if settings.modifierTapEnabled && Permissions.isTrusted {
            modifierTap.start()
        } else {
            modifierTap.stop()
        }
    }
}
