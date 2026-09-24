//
//  OnboardingView.swift
//  NotchKit
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI
import AVFoundation

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            OnboardingBackground()

            switch step {
            case .welcome:
                WelcomeView {
                    advance(to: .cameraPermission)
                }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "NotchKit includes a mirror that lets you quickly check your appearance right from the notch. Camera access is used only to show this live preview, and you can turn the feature off at any time.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            await requestCameraPermission()
                            advance(to: .calendarPermission)
                        }
                    },
                    onSkip: {
                        advance(to: .calendarPermission)
                    }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "NotchKit can show your upcoming events in one place. Calendar access is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                            await requestCalendarPermission()
                            advance(to: .remindersPermission)
                        }
                    },
                    onSkip: {
                        advance(to: .remindersPermission)
                    }
                )
                .transition(.opacity)

            case .remindersPermission:
                PermissionRequestView(
                    icon: Image(systemName: "checklist"),
                    title: "Enable Reminders Access",
                    description: "NotchKit can show scheduled reminders alongside calendar events. Reminders access is needed to display them.",
                    privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                    onAllow: {
                        Task {
                            await requestRemindersPermission()
                            advance(to: .accessibilityPermission)
                        }
                    },
                    onSkip: {
                        advance(to: .accessibilityPermission)
                    }
                )
                .transition(.opacity)
                
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access lets NotchKit replace system media and brightness notifications with custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            await requestAccessibilityPermission()
                            advance(to: .musicPermission)
                        }
                    },
                    onSkip: {
                        advance(to: .musicPermission)
                    }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        BoringViewCoordinator.shared.firstLaunch = false
                        advance(to: .finished)
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
        .tint(.effectiveAccent)
    }

    private func advance(to nextStep: OnboardingStep) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) {
            step = nextStep
        }
    }

    // MARK: - Permission Request Logic

    func requestCameraPermission() async {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func requestCalendarPermission() async {
        _ = try? await calendarService.requestAccess(to: .event)
    }

    func requestRemindersPermission() async {
        _ = try? await calendarService.requestAccess(to: .reminder)
    }
    
    func requestAccessibilityPermission() async {
        // Request from the app process, which owns the event tap.
        await MainActor.run {
            HostPermissionService.shared.requestHUDInputAccess()
        }
    }
}

struct OnboardingBackground: View {
    var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()

            LinearGradient(
                colors: [Color.effectiveAccent.opacity(0.12), .clear, Color.black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
        .accessibilityHidden(true)
    }
}

struct OnboardingBrandMark: View {
    var size: CGFloat = 54

    var body: some View {
        Image("NotchKitBrand")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel("NotchKit")
    }
}
