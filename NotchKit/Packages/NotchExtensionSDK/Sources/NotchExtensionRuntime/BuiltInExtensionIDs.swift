//
//  BuiltInExtensionIDs.swift
//  NotchExtensionRuntime
//
//  Stable identities for the built-in first-party extensions.
//

import NotchExtensionSDK

/// Stable identities used by the built-in first-party extensions.
///
/// These are intentionally centralised so the app host, router, and settings hub
/// agree on the same strings.
public enum BuiltInExtensionIDs {
    public static let home: ExtensionIdentity = {
        // The literal is a compile-time constant and validated by tests.
        guard let id = try? ExtensionIdentity("com.notchkit.home") else {
            preconditionFailure("Invalid built-in Home identity")
        }
        return id
    }()

    public static let shelf: ExtensionIdentity = {
        guard let id = try? ExtensionIdentity("com.notchkit.shelf") else {
            preconditionFailure("Invalid built-in Shelf identity")
        }
        return id
    }()

    /// Calendar & Reminders.
    public static let calendar = make("com.notchkit.calendar", "calendar")
    /// Media (music live activity and controls).
    public static let media = make("com.notchkit.media", "media")
    /// HUD (volume/brightness/keyboard-backlight indicators and media-key
    /// interception).
    public static let hud = make("com.notchkit.hud", "hud")
    /// Camera Mirror.
    public static let camera = make("com.notchkit.camera", "camera")

    /// The six user-toggleable first-party features, in presentation order.
    ///
    /// Home is intentionally excluded: it is required and has no toggle.
    public static var toggleableFeatures: [ExtensionIdentity] {
        [shelf, calendar, media, hud, camera]
    }

    public static let homeDestination = DestinationID("com.notchkit.destination.home")
    public static let shelfDestination = DestinationID("com.notchkit.destination.shelf")

    public static let shelfSettings = DestinationID("com.notchkit.settings.shelf")
    public static let calendarSettings = DestinationID("com.notchkit.settings.calendar")
    public static let mediaSettings = DestinationID("com.notchkit.settings.media")
    public static let hudSettings = DestinationID("com.notchkit.settings.hud")
    public static let cameraSettings = DestinationID("com.notchkit.settings.camera")

    public static let batteryContribution = ContributionID("com.notchkit.contribution.battery")
    public static let inlineHUDContribution = ContributionID("com.notchkit.contribution.inline-hud")
    public static let musicContribution = ContributionID("com.notchkit.contribution.music")
    public static let idleFaceContribution = ContributionID("com.notchkit.contribution.idle-face")

    private static func make(_ rawValue: String, _ label: String) -> ExtensionIdentity {
        guard let id = try? ExtensionIdentity(rawValue) else {
            preconditionFailure("Invalid built-in \(label) identity")
        }
        return id
    }
}
