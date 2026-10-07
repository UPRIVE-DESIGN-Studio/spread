import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section("Hotkeys") {
                KeyboardShortcuts.Recorder("Tile frontmost app", name: .tileFrontmost)
                KeyboardShortcuts.Recorder("Spread across all screens", name: .tileAllScreens)
                KeyboardShortcuts.Recorder("Undo last tile", name: .undoTile)
                Toggle(isOn: $settings.modifierTapEnabled) {
                    Text("Tap ⌃⌥⌘ to tile onto the screen under the mouse")
                    Text("Press and release Control, Option and Command together, with no other key.")
                }
            }

            Section("Layout") {
                LabeledContent("Gap") {
                    HStack {
                        Slider(value: $settings.gap, in: SettingsStore.gapRange, step: 1)
                        Text("\(Int(settings.gap)) px")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Picker("Tile onto", selection: $settings.screenTarget) {
                    Text("Screen under mouse").tag(SettingsStore.ScreenTarget.underMouse)
                    ForEach(Display.all(), id: \.id) { display in
                        Text(display.name).tag(SettingsStore.ScreenTarget.display(id: display.id))
                    }
                    if case .display(let id) = settings.screenTarget, Display.with(id: id) == nil {
                        Text("Disconnected display (using screen under mouse)").tag(settings.screenTarget)
                    }
                    Text("All screens").tag(SettingsStore.ScreenTarget.allScreens)
                    Text("Each screen in place").tag(SettingsStore.ScreenTarget.perScreen)
                }
                Toggle("Include minimized windows", isOn: $settings.includeMinimized)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                if let error = settings.launchAtLoginError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { settings.refreshLaunchAtLogin() }
    }
}
