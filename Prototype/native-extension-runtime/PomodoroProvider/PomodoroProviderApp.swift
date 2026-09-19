import SwiftUI

@main
struct PomodoroProviderApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 18) {
                Image(systemName: "timer.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red.gradient)
                Text("Pomodoro Focus")
                    .font(.largeTitle.bold())
                Text("The provider is installed. Open the NotchKit native-extension host and enable Pomodoro through Manage System Extensions.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 440)
            }
            .padding(48)
            .frame(minWidth: 560, minHeight: 360)
        }
    }
}
