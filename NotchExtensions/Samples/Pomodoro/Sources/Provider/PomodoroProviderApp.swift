import SwiftUI

@main
struct PomodoroProviderApp: App {
    var body: some Scene {
        WindowGroup {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.16, green: 0.045, blue: 0.055), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {
                    Image(systemName: "timer.circle.fill")
                        .font(.system(size: 72, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .red)
                        .accessibilityHidden(true)

                    Text("Pomodoro for NotchKit")
                        .font(.largeTitle.bold())

                    Text("This provider supplies a focused timer, a compact open-notch view, and a closed-notch status control.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)

                    Label("Manage this extension in NotchKit Settings", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .padding(48)
            }
            .frame(minWidth: 620, minHeight: 420)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
