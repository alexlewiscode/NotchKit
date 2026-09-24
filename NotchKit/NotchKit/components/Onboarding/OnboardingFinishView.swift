//
//  OnboardingFinishView.swift
//  NotchKit
//
//  Created by Alexander on 2025-06-23.
//


import SwiftUI

struct OnboardingFinishView: View {
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFinishFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            ZStack {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.14))
                    .frame(width: 178, height: 178)
                    .blur(radius: 24)
                if !reduceMotion {
                    SparkleView(isEnabled: true)
                        .frame(width: 220, height: 190)
                        .opacity(0.35)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                OnboardingBrandMark(size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.effectiveAccent)
                            .background(Circle().fill(.background).padding(2))
                    }
            }
            .frame(height: 190)

            Text("You're All Set")
                .font(.system(size: 31, weight: .bold, design: .rounded))

            Text("NotchKit is ready. Fine-tune your experience now, or jump in and make more of your notch.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 38)
                .padding(.top, 12)

            Spacer(minLength: 34)

            VStack(spacing: 12) {
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .focused($isFinishFocused)
                    .accessibilityHint("Closes setup")

                Button(action: onOpenSettings) {
                    Label("Customize in Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)
                .controlSize(.large)
                .accessibilityHint("Closes setup and opens NotchKit settings")
            }
            .padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFinishFocused = true }
    }
}

#Preview {
    OnboardingFinishView(onFinish: { }, onOpenSettings: { })
}
