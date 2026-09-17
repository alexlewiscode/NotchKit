//
//  FeatureLifecycle.swift
//  NotchKit
//
//  Host-owned lifecycle adapters for the not-yet-extracted features.
//
//  Each adapter is the single owner of its feature service while the feature is
//  enabled. `activate()` starts exactly one service instance and registers
//  teardown with the activation's cancellation bag; `deactivate()` stops it.
//  Both must be safe to call after a partial or failed activation, and to call
//  more than once. Persisted preferences, selections, credentials, and stored
//  data are never cleared here.
//

import Defaults
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Calendar & Reminders: owns the calendar observers and refresh work.
@MainActor
final class CalendarFeature: NotchExtension {
    private let context: ExtensionContext
    private let manager: CalendarManager

    init(context: ExtensionContext, manager: CalendarManager) {
        self.context = context
        self.manager = manager
    }

    func activate() async throws {
        context.cancellation.add { [weak manager] in manager?.stop() }
        manager.start()
    }

    func deactivate() {
        manager.stop()
        context.cancellation.cancelAll()
    }
}

/// Media: owns music controllers, artwork, and playback observation.
///
/// Disabling never pauses or otherwise alters playback in an external music
/// application; it only stops observing and releases the controller.
@MainActor
final class MediaFeature: NotchExtension {
    private let context: ExtensionContext
    private let manager: MusicManager

    init(context: ExtensionContext, manager: MusicManager) {
        self.context = context
        self.manager = manager
    }

    func activate() async throws {
        context.cancellation.add { [weak manager] in manager?.stop() }
        manager.start()
    }

    func deactivate() {
        manager.stop()
        context.cancellation.cancelAll()
    }
}

/// Camera Mirror: owns device availability monitoring and the capture session.
///
/// Activation does not request camera access and does not start capture;
/// accessing the camera remains an explicit user action when the mirror opens.
@MainActor
final class CameraFeature: NotchExtension {
    private let context: ExtensionContext
    private let manager: WebcamManager

    init(context: ExtensionContext, manager: WebcamManager) {
        self.context = context
        self.manager = manager
    }

    func activate() async throws {
        context.cancellation.add { [weak manager] in manager?.stop() }
        manager.start()
    }

    func deactivate() {
        manager.stop()
        context.cancellation.cancelAll()
    }
}

/// HUD: owns media-key interception and the volume/brightness observers.
///
/// Enabling requires input access. The capability and the request are app-side
/// (see `InputAccessAuthorizing`): the event tap is installed by the app
/// process, so the app's own capability is what matters. Status is checked
/// without prompting; the settings row offers an explicit "Grant Access" action.
/// Disabling restores normal system input handling.
@MainActor
final class HUDFeature: NotchExtension {
    private let context: ExtensionContext
    private let interceptor: any HUDIntercepting
    private let inputAccess: InputAccessAuthorizing

    init(
        context: ExtensionContext,
        interceptor: any HUDIntercepting = MediaKeyInterceptor.shared,
        inputAccess: InputAccessAuthorizing = SystemInputAccessAuthorization()
    ) {
        self.context = context
        self.interceptor = interceptor
        self.inputAccess = inputAccess
    }

    func activate() async throws {
        context.cancellation.add { [interceptor] in
            interceptor.stop()
            VolumeManager.shared.stop()
            BrightnessManager.shared.stop()
            KeyboardBacklightManager.shared.stop()
        }

        VolumeManager.shared.start()
        BrightnessManager.shared.start()
        KeyboardBacklightManager.shared.start()

        // Attempt the tap first. It is the authoritative capability test;
        // `AXIsProcessTrusted()` is not a reliable gate for a modifying global
        // tap and a sandboxed app is not promised to report true.
        let running = await interceptor.start()
        guard running else {
            // Clean up the partial startup, then classify it using the status
            // from the same process that attempted the protected operation.
            context.cancellation.cancelAll()
            switch inputAccess.status() {
            case .requiresPermission:
                throw ExtensionActivationError.permissionRequired(.accessibility)
            case .checkFailed(let message):
                throw HUDActivationFailure.statusCheckFailed(message)
            case .granted:
                throw HUDActivationFailure.mediaKeyInterceptionUnavailable
            }
        }
    }

    func deactivate() {
        interceptor.stop()
        VolumeManager.shared.stop()
        BrightnessManager.shared.stop()
        KeyboardBacklightManager.shared.stop()
        // Dismiss only a HUD-owned presentation; never a Media sneak peek.
        BoringViewCoordinator.shared.dismissSneakPeek(
            kinds: [.volume, .brightness, .backlight, .mic]
        )
        context.cancellation.cancelAll()
    }
}

/// The interception surface HUD owns. Implemented by `MediaKeyInterceptor` in
/// production and by a fake in tests.
@MainActor
protocol HUDIntercepting: AnyObject {
    /// Ensures a tap is installed, returning whether one is running. Never
    /// prompts.
    func start() async -> Bool
    func stop()
    var isRunning: Bool { get }
}

/// A non-permission failure while starting HUD. Mapped by the host to `.failed`,
/// so it is never mistaken for a grantable permission gate.
enum HUDActivationFailure: LocalizedError, Equatable {
    case mediaKeyInterceptionUnavailable
    case statusCheckFailed(String)

    var errorDescription: String? {
        switch self {
        case .mediaKeyInterceptionUnavailable:
            return "HUD access is granted, but media-key interception could not start."
        case .statusCheckFailed(let message):
            return "HUD permission status could not be checked: \(message)"
        }
    }
}

/// Shelf: owns share-provider discovery and the drag/auto-open activation
/// signal. Stored items, bookmarks, and sharing preferences are untouched.
@MainActor
final class ShelfExtension: NotchExtension {
    private let context: ExtensionContext

    init(context: ExtensionContext) {
        self.context = context
    }

    func activate() async throws {
        context.cancellation.add {
            QuickShareService.shared.stop()
        }
        QuickShareService.shared.start()
        NotificationCenter.default.post(name: .shelfEnabledChanged, object: nil)
    }

    func deactivate() {
        QuickShareService.shared.stop()
        NotificationCenter.default.post(name: .shelfEnabledChanged, object: nil)
        context.cancellation.cancelAll()
    }

    func openDestinations() -> [NotchOpenDestination] {
        [
            NotchOpenDestination(
                id: BuiltInExtensionIDs.shelfDestination,
                title: "Shelf",
                iconSystemName: "tray.fill",
                order: 1,
                isAvailable: { true },
                makeView: { AnyView(ShelfView()) }
            )
        ]
    }
}

extension Notification.Name {
    /// Posted when the Shelf feature's enabled state changes, so host-owned drag
    /// detectors and auto-open triggers can re-evaluate.
    static let shelfEnabledChanged = Notification.Name("notchkit.shelfEnabledChanged")
}
