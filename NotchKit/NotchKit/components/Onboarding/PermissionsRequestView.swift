//
//  PermissionsRequestView.swift
//  NotchKit
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let privacyNote: LocalizedStringKey?
    let onAllow: () -> Void
    let onSkip: () -> Void
    @State private var isRequesting = false
    @FocusState private var focusedAction: Action?

    private enum Action: Hashable {
        case skip
        case allow
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingBrandMark(size: 34)
                Spacer()
                Text("PRIVACY")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.3)
            }
            .padding(.bottom, 30)

            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.effectiveAccent.opacity(0.13))
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 46)
                    .foregroundStyle(Color.effectiveAccent.gradient)
            }
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)

            Text(title)
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.top, 24)

            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)

            if let privacyNote = privacyNote {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(Color.effectiveAccent)
                    Text(privacyNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 22)
                .accessibilityElement(children: .combine)
            }

            Spacer(minLength: 22)

            HStack(spacing: 12) {
                Button("Not Now") {
                    guard !isRequesting else { return }
                    onSkip()
                }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .focused($focusedAction, equals: .skip)

                Button {
                    guard !isRequesting else { return }
                    isRequesting = true
                    onAllow()
                } label: {
                    HStack(spacing: 8) {
                        if isRequesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isRequesting ? "Waiting for Permission..." : "Allow Access")
                    }
                    .frame(minWidth: 126)
                }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .focused($focusedAction, equals: .allow)
            }
            .disabled(isRequesting)
        }
        .padding(.horizontal, 34)
        .padding(.top, 28)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focusedAction = .allow }
        .accessibilityElement(children: .contain)
    }
}
