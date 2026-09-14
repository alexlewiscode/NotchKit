//
//  BuiltInExtensions.swift
//  NotchKit
//
//  First-party extension descriptors registered through the catalog.
//

import Defaults
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Descriptors for the built-in first-party extensions.
///
/// Home and Shelf keep their existing views and behaviour; they are simply
/// registered through the extension catalog so open-content switching uses
/// stable destination ids rather than a closed enum.
enum BuiltInExtensions {
    static func descriptors() -> [ExtensionDescriptor] {
        [homeDescriptor(), shelfDescriptor()]
    }

    static func homeDescriptor() -> ExtensionDescriptor {
        ExtensionDescriptor(
            id: BuiltInExtensionIDs.home,
            displayName: "Home",
            summary: "Music controls, calendar, and camera preview.",
            iconSystemName: "house.fill",
            capabilities: [.openDestination],
            defaultEnabled: true,
            openDestinations: [
                NotchOpenDestination(
                    id: BuiltInExtensionIDs.homeDestination,
                    title: "Home",
                    iconSystemName: "house.fill",
                    order: 0,
                    isAvailable: { true },
                    makeView: { AnyView(NotchHomeView()) }
                )
            ]
        )
    }

    static func shelfDescriptor() -> ExtensionDescriptor {
        ExtensionDescriptor(
            id: BuiltInExtensionIDs.shelf,
            displayName: "Shelf",
            summary: "Drag and drop files into the notch.",
            iconSystemName: "tray.fill",
            capabilities: [.openDestination, .settingsDestination],
            defaultEnabled: true,
            openDestinations: [
                NotchOpenDestination(
                    id: BuiltInExtensionIDs.shelfDestination,
                    title: "Shelf",
                    iconSystemName: "tray.fill",
                    order: 1,
                    isAvailable: { Defaults[.boringShelf] },
                    makeView: { AnyView(ShelfView()) }
                )
            ],
            settingsDestinations: [
                ExtensionSettingsDestination(
                    id: BuiltInExtensionIDs.shelfSettings,
                    title: "Shelf",
                    iconSystemName: "tray.fill",
                    isAvailable: { Defaults[.boringShelf] },
                    makeView: { AnyView(Shelf()) }
                )
            ]
        )
    }
}