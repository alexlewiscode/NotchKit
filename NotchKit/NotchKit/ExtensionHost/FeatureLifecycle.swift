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
/// Enabling requires the accessibility permission. It is checked without
/// prompting; the settings row offers an explicit "Grant Access" action that
/// prompts and then retries, so toggling never produces a surprise prompt.
/// Disabling restores normal system input handling.
@MainActor
final class HUDFeature: NotchExtension {
    private let context: ExtensionContext

    init(context: ExtensionContext) {
        self.context = context
    }

    func activate() async throws {
        // Use the same accessibility trust source the event tap requires (the
        // XPC helper), so "Grant Access" and the gate can never disagree.
        let authorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        guard authorized else {
            throw ExtensionActivationError.permissionRequired(.accessibility)
        }

        context.cancellation.add {
            MediaKeyInterceptor.shared.stop()
            VolumeManager.shared.stop()
            BrightnessManager.shared.stop()
            KeyboardBacklightManager.shared.stop()
        }

        VolumeManager.shared.start()
        BrightnessManager.shared.start()
        KeyboardBacklightManager.shared.start()
        await MediaKeyInterceptor.shared.start()

        // If the tap could not be installed (for example the permission was
        // revoked between the check and the install), report an accurate state
        // instead of claiming HUD is active.
        guard MediaKeyInterceptor.shared.isRunning else {
            throw ExtensionActivationError.permissionRequired(.accessibility)
        }
    }

    func deactivate() {
        MediaKeyInterceptor.shared.stop()
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
