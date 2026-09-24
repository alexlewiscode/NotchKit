//
//  WhatsNewView.swift
//  NotchKit
//
//  Created by Richard Kunkli on 09/08/2024.
//

import SwiftUI

struct WhatsNewView: View {
    @Binding var isPresented: Bool
    @FocusState private var isDismissFocused: Bool
    
    var body: some View {
        ZStack {
            OnboardingBackground()

            VStack(spacing: 0) {
                OnboardingBrandMark(size: 58)

                Text("What's New in NotchKit")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .padding(.top, 16)

                Text("A more refined experience, built for your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)

                VStack(spacing: 12) {
                    WhatsNewFeature(
                        icon: "rectangle.3.group.fill",
                        title: "A refreshed workspace",
                        detail: "A clearer, more polished interface keeps your controls close at hand."
                    )
                    WhatsNewFeature(
                        icon: "bolt.fill",
                        title: "Smoother by design",
                        detail: "Interaction and performance improvements make NotchKit feel more responsive."
                    )
                    WhatsNewFeature(
                        icon: "checkmark.shield.fill",
                        title: "Quality throughout",
                        detail: "Reliability fixes deliver a more consistent experience across the app."
                    )
                }
                .padding(.top, 24)

                Button("Continue") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .focused($isDismissFocused)
                .padding(.top, 26)
            }
            .padding(32)
        }
        .frame(minWidth: 420, idealWidth: 480, minHeight: 500, idealHeight: 540)
        .tint(.effectiveAccent)
        .onAppear { isDismissFocused = true }
        .onExitCommand { isPresented = false }
    }
}

private struct WhatsNewFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.effectiveAccent.gradient)
                .frame(width: 40, height: 40)
                .background(Color.effectiveAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewView(isPresented: .constant(true))
}
