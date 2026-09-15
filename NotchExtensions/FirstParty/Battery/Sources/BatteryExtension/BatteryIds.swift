//
//  BatteryIds.swift
//  BatteryExtension
//
//  Stable identities and the metadata-only manifest for the Battery extension.
//

import Foundation
import NotchExtensionSDK

/// Stable identities for the Battery extension's contributions.
public enum BatteryIds {
    /// The extension identity. Stable across releases; never rename.
    public static let identity: ExtensionIdentity = {
        guard let id = try? ExtensionIdentity("com.notchkit.battery") else {
            preconditionFailure("Invalid Battery extension identity")
        }
        return id
    }()

    /// The closed-notch battery notification contribution.
    public static let contribution = ContributionID("com.notchkit.contribution.battery")
    /// The Battery settings page.
    public static let settingsDestination = DestinationID("com.notchkit.settings.battery")
}

/// The runtime-free manifest for the Battery extension.
///
/// Metadata listing must not start any service; this value contains no
/// instances and no closures.
public enum BatteryManifest {
    /// The canonical metadata. Matches `manifest.json` in this package.
    public static func metadata() throws -> ExtensionMetadata {
        ExtensionMetadata(
            id: BatteryIds.identity,
            displayName: "Battery",
            summary: "Shows charging status and power notifications in the closed notch.",
            iconSystemName: "battery.100",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            apiVersion: .current,
            supportedHostVersions: ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 0, patch: 0)
            ),
            supportedSDKVersions: ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
                maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
            ),
            capabilities: [.closedNotchContribution, .settingsDestination],
            artifactKind: .compiledIn,
            entryPoints: [
                ExtensionEntryPoint(
                    id: BatteryIds.contribution.rawValue,
                    kind: .closedNotchContribution
                ),
                ExtensionEntryPoint(
                    id: BatteryIds.settingsDestination.rawValue,
                    kind: .settingsDestination
                ),
            ],
            defaultEnabled: true,
            source: .firstParty
        )
    }
}