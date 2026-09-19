import SwiftUI

struct PomodoroView: View {
    private let focusDuration: TimeInterval = 25 * 60

    @State private var remaining: TimeInterval = 25 * 60
    @State private var endDate: Date?
    @State private var completedSessions = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.045, blue: 0.06), Color(red: 0.025, green: 0.02, blue: 0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let seconds = displayedRemaining(at: context.date)
                VStack(spacing: 24) {
                    HStack {
                        Label("FOCUS", systemImage: "circle.fill")
                            .font(.caption.weight(.black))
                            .tracking(2.4)
                            .foregroundStyle(.red)
                        Spacer()
                        Text("\(completedSessions) completed")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ZStack {
                        Circle()
                            .stroke(.white.opacity(0.08), lineWidth: 15)
                        Circle()
                            .trim(from: 0, to: max(0.001, seconds / focusDuration))
                            .stroke(
                                AngularGradient(colors: [.red, .orange, .red], center: .center),
                                style: StrokeStyle(lineWidth: 15, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: .red.opacity(0.4), radius: 20)

                        VStack(spacing: 6) {
                            Text(formatted(seconds))
                                .font(.system(size: 62, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(endDate == nil ? "READY FOR DEEP WORK" : "SESSION IN PROGRESS")
                                .font(.caption2.bold())
                                .tracking(1.5)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 250, height: 250)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Focus timer")
                    .accessibilityValue(formatted(seconds))

                    HStack(spacing: 12) {
                        Button {
                            toggle(at: context.date)
                        } label: {
                            Label(endDate == nil ? "Start" : "Pause", systemImage: endDate == nil ? "play.fill" : "pause.fill")
                                .frame(minWidth: 92)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.large)

                        Button("Reset", systemImage: "arrow.counterclockwise") {
                            endDate = nil
                            remaining = focusDuration
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(32)
            }
        }
        .frame(minWidth: 430, minHeight: 470)
    }

    private func displayedRemaining(at date: Date) -> TimeInterval {
        guard let endDate else { return remaining }
        return max(0, endDate.timeIntervalSince(date))
    }

    private func toggle(at date: Date) {
        if let endDate {
            remaining = max(0, endDate.timeIntervalSince(date))
            self.endDate = nil
            if remaining == 0 {
                completedSessions += 1
                remaining = focusDuration
            }
        } else {
            endDate = date.addingTimeInterval(remaining)
        }
    }

    private func formatted(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
