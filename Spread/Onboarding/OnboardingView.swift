import SwiftUI

struct OnboardingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.split.3x3")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.tint)

            Text("Spread needs Accessibility access")
                .font(.title2.weight(.semibold))

            Text("""
                To move and resize other apps' windows, macOS requires you to allow Spread under \
                Privacy & Security › Accessibility. Spread only reads window positions and sizes; \
                it never reads window contents and never uses the network.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Open System Settings") {
                Permissions.prompt()
                Permissions.openSettingsPane()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Text("This window closes by itself once access is granted.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 420)
    }
}
