//
//  FeatureEmptyStateView.swift
//  NotchKit
//
//  Shown in the expanded notch content area when every optional feature is off.
//

import SwiftUI

/// The expanded-notch empty state: the existing first-launch hello animation
/// with a short prompt underneath. Reuses `HelloAnimation` rather than a new
/// asset or a copy of its implementation.
struct FeatureEmptyStateView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replay = 0

    var body: some View {
        VStack(spacing: 10) {
            HelloAnimation {
                // The hello animation is transient once it completes; replay it
                // so the illustration stays present while the notch is empty.
                // Reduce Motion holds a single static frame instead.
                guard !reduceMotion else { return }
                replay &+= 1
            }
            .id(replay)
            .frame(width: 220, height: 72)
            .accessibilityHidden(true)

            Text("Enable some extensions to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    FeatureEmptyStateView()
        .frame(width: 640, height: 190)
        .background(.black)
        .preferredColorScheme(.dark)
}
