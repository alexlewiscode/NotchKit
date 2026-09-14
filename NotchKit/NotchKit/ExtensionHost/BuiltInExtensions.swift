//
//  BuiltInExtensions.swift
//  NotchKit
//
//  First-party extension definitions registered through the catalog.
//

import Defaults
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Definitions for the built-in first-party extensions.
///
/// Home and Shelf keep their existing views and behaviour; they are registered
/// through the extension catalog so open-content switching uses stable
/// destination ids and content is produced only while the extension is active.
enum BuiltInExtensions {
    static func definitions() -> [ExtensionDefinition] {
        [homeDefinition(), shelfDefinition()]
    }

    static func homeDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.home,
                displayName: "Home",
                summary: "Music controls, calendar, and camera preview.",
                iconSystemName: "house.fill",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.openDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: BuiltInExtensionIDs.homeDestination.rawValue,
                        kind: .openDestination
                    )
                ],
                defaultEnabled: true
            )
        ) { _ in
            HomeExtension()
        }
    }

    static func shelfDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.shelf,
                displayName: "Shelf",
                summary: "Drag and drop files into the notch.",
                iconSystemName: "tray.fill",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.openDestination, .settingsDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: BuiltInExtensionIDs.shelfDestination.rawValue,
                        kind: .openDestination
                    ),
                    ExtensionEntryPoint(
                        id: BuiltInExtensionIDs.shelfSettings.rawValue,
                        kind: .settingsDestination
                    )
                ],
                defaultEnabled: true
            )
        ) { _ in
            ShelfExtension()
        }
    }

    private static var supportedHostVersions: ExtensionVersionRange {
        ExtensionVersionRange(minimum: ExtensionVersion(major: 1, minor: 0, patch: 0))
    }

    private static var supportedSDKVersions: ExtensionVersionRange {
        ExtensionVersionRange(
            minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
            maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
        )
    }
}

/// The activated Home extension. Contributes the Home tab while active.
@MainActor
final class HomeExtension: NotchExtension {
    func openDestinations() -> [NotchOpenDestination] {
        [
            NotchOpenDestination(
                id: BuiltInExtensionIDs.homeDestination,
                title: "Home",
                iconSystemName: "house.fill",
                order: 0,
                isAvailable: { true },
                makeView: { AnyView(NotchHomeView()) }
            )
        ]
    }
}

/// The activated Shelf extension. Contributes the Shelf tab and settings page
/// while active.
@MainActor
final class ShelfExtension: NotchExtension {
    func openDestinations() -> [NotchOpenDestination] {
        [
            NotchOpenDestination(
                id: BuiltInExtensionIDs.shelfDestination,
                title: "Shelf",
                iconSystemName: "tray.fill",
                order: 1,
                isAvailable: { Defaults[.boringShelf] },
                makeView: { AnyView(ShelfView()) }
            )
        ]
    }

    func settingsDestinations() -> [ExtensionSettingsDestination] {
        [
            ExtensionSettingsDestination(
                id: BuiltInExtensionIDs.shelfSettings,
                title: "Shelf",
                iconSystemName: "tray.fill",
                isAvailable: { Defaults[.boringShelf] },
                makeView: { AnyView(Shelf()) }
            )
        ]
    }
}
