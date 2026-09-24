//
//  MusicControllerSelectionView.swift
//  NotchKit
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import Defaults


struct MusicControllerSelectionView: View {
    let onContinue: () -> Void

    @Default(.mediaController) var mediaController
    
    private var availableMediaControllers: [MediaControllerType] {
        if MusicManager.shared.isNowPlayingDeprecated {
            return MediaControllerType.allCases.filter { $0 != .nowPlaying }
        } else {
            return MediaControllerType.allCases
        }
    }
    
    @State private var selectedMediaController: MediaControllerType = Defaults[.mediaController]
    @FocusState private var focusedController: MediaControllerType?
    @FocusState private var isContinueFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                OnboardingBrandMark(size: 34)
                Spacer()
                Text("MUSIC")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1.3)
            }
            .padding(.horizontal, 30)
            .padding(.top, 28)

            Text("Choose a Music Source")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .padding(.top, 20)

            Text("Select the music source you want to use. You can change this later in the app settings.")
                .multilineTextAlignment(.center)
                .font(.body)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .padding(.horizontal, 34)
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(availableMediaControllers) { controller in
                        Button {
                            selectedMediaController = controller
                        } label: {
                            ControllerOptionView(
                                controller: controller,
                                isSelected: selectedMediaController == controller
                            )
                        }
                        .buttonStyle(.plain)
                        .focused($focusedController, equals: controller)
                        .accessibilityLabel(controller.rawValue)
                        .accessibilityValue(selectedMediaController == controller ? "Selected" : "Not selected")
                        .accessibilityHint(controller.description)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 20)
            }
            .scrollDisabled(availableMediaControllers.count <= 4)

            if selectedMediaController == .youtubeMusic,
               let url = URL(string: "https://github.com/pear-devs/pear-desktop") {
                Link("Learn about the required third-party client", destination: url)
                    .font(.caption)
                    .padding(.bottom, 10)
            }

            Button("Continue") {
                mediaController = selectedMediaController
                NotificationCenter.default.post(
                    name: Notification.Name.mediaControllerChanged,
                    object: nil
                )
                onContinue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .focused($isContinueFocused)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if !availableMediaControllers.contains(selectedMediaController),
               let firstController = availableMediaControllers.first {
                selectedMediaController = firstController
            }
            focusedController = selectedMediaController
        }
        .onMoveCommand(perform: moveSelection)
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down,
              let currentIndex = availableMediaControllers.firstIndex(of: selectedMediaController) else { return }
        let offset = direction == .up ? -1 : 1
        let nextIndex = min(max(currentIndex + offset, 0), availableMediaControllers.count - 1)
        selectedMediaController = availableMediaControllers[nextIndex]
        focusedController = selectedMediaController
    }
}

struct ControllerOptionView: View {
    let controller: MediaControllerType
    let isSelected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundColor(isSelected ? .effectiveAccent : .secondary.opacity(0.5))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isSelected)

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.rawValue)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(controller.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.effectiveAccent.opacity(0.14) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.3), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
    }
}


extension MediaControllerType {
    var description: String {
        switch self {
        case .nowPlaying:
            return "Works with most media apps, including browsers, to detect what's playing. Note: This may be removed in a future macOS version."
        case .spotify:
            return "Connects directly to the Spotify app."
        case .appleMusic:
            return "Connects directly to the Apple Music app."
        case .youtubeMusic:
            return "Requires a third-party client with API plugin enabled."
        }
    }
}

#Preview {
    MusicControllerSelectionView(onContinue: {})
        .frame(width: 400, height: 600)
}
