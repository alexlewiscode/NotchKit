//
//  BuiltInExtensionIDs.swift
//  NotchExtensions
//
//  Stable identities for the built-in first-party extensions.
//

import NotchAPI

/// Stable identities used by the built-in first-party extensions.
///
/// These are intentionally centralised so the app host, router, and settings hub
/// agree on the same strings.
public enum BuiltInExtensionIDs {
    public static let home: ExtensionIdentity = {
        // The literal is a compile-time constant and validated by tests.
        guard let id = try? ExtensionIdentity("com.boringnotch.home") else {
            preconditionFailure("Invalid built-in Home identity")
        }
        return id
    }()

    public static let shelf: ExtensionIdentity = {
        guard let id = try? ExtensionIdentity("com.boringnotch.shelf") else {
            preconditionFailure("Invalid built-in Shelf identity")
        }
        return id
    }()

    public static let homeDestination = DestinationID("com.boringnotch.destination.home")
    public static let shelfDestination = DestinationID("com.boringnotch.destination.shelf")

    public static let shelfSettings = DestinationID("com.boringnotch.settings.shelf")

    public static let batteryContribution = ContributionID("com.boringnotch.contribution.battery")
    public static let inlineHUDContribution = ContributionID("com.boringnotch.contribution.inline-hud")
    public static let musicContribution = ContributionID("com.boringnotch.contribution.music")
    public static let idleFaceContribution = ContributionID("com.boringnotch.contribution.idle-face")
}
