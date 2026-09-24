//
//  WelcomeView.swift
//  NotchKit
//
//  Created by Richard Kunkli on 2024. 09. 26..
//

import SwiftUI

struct WelcomeView: View {
    var onGetStarted: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isGetStartedFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 54)

            ZStack {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.16))
                    .frame(width: 210, height: 210)
                    .blur(radius: 36)

                if !reduceMotion {
                    SparkleView(isEnabled: true)
                        .frame(width: 260, height: 230)
                        .opacity(0.45)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }

                OnboardingBrandMark(size: 108)
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
            }
            .frame(height: 220)

            Text("Welcome to NotchKit")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Make more of your notch with focused controls, useful glanceable information, and a workspace that feels at home on your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)
                .padding(.horizontal, 36)

            Spacer(minLength: 36)

            Button("Get Started") {
                onGetStarted?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .focused($isGetStartedFocused)
            .accessibilityHint("Begins setup")

            Text("Setup takes about a minute")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
                .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isGetStartedFocused = true }
    }
}

#Preview {
    WelcomeView()
}
