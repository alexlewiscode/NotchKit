//
//  LegacyFeatureSettings.swift
//  NotchKit
//
//  Explicit host-owned settings adapters for the features that are not
//  extracted in this milestone: Calendar & Reminders, Media, HUD, and Camera
//  Mirror. The pages read configuration only and are served from the
//  authoritative `SettingsCatalog`; they never activate an extension.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Host-owned settings catalog entries for not-yet-extracted features.
enum LegacyFeatureSettings {
    static let calendarFeatureID = FeatureSettingsID("com.notchkit.feature.calendar")
    static let mediaFeatureID = FeatureSettingsID("com.notchkit.feature.media")
    static let hudFeatureID = FeatureSettingsID("com.notchkit.feature.hud")
    static let cameraFeatureID = FeatureSettingsID("com.notchkit.feature.camera")

    static let calendarDestinationID = DestinationID("com.notchkit.settings.calendar")
    static let mediaDestinationID = DestinationID("com.notchkit.settings.media")
    static let hudDestinationID = DestinationID("com.notchkit.settings.hud")
    static let cameraDestinationID = DestinationID("com.notchkit.settings.camera")

    /// Presentation order shared with `NotchKitRuntime`.
    static let calendarOrder = 10
    static let mediaOrder = 30
    static let hudOrder = 40
    static let cameraOrder = 50

    /// The configuration-only entries appended after definition-backed entries.
    static func adapters() -> [SettingsCatalogEntry] {
        [
            SettingsCatalogEntry(
                id: calendarFeatureID,
                displayName: "Calendar & Reminders",
                iconSystemName: "calendar",
                owner: nil,
                management: .configurationOnly,
                order: calendarOrder,
                destinations: [
                    ExtensionSettingsDestination(
                        id: calendarDestinationID,
                        title: "Calendar & Reminders",
                        iconSystemName: "calendar",
                        isAvailable: { true },
                        makeView: { AnyView(CalendarSettingsPage()) }
                    )
                ]
            ),
            SettingsCatalogEntry(
                id: mediaFeatureID,
                displayName: "Media",
                iconSystemName: "play.laptopcomputer",
                owner: nil,
                management: .configurationOnly,
                order: mediaOrder,
                destinations: [
                    ExtensionSettingsDestination(
                        id: mediaDestinationID,
                        title: "Media",
                        iconSystemName: "play.laptopcomputer",
                        isAvailable: { true },
                        makeView: { AnyView(MediaSettingsPage()) }
                    )
                ]
            ),
            SettingsCatalogEntry(
                id: hudFeatureID,
                displayName: "HUD",
                iconSystemName: "dial.medium.fill",
                owner: nil,
                management: .configurationOnly,
                order: hudOrder,
                destinations: [
                    ExtensionSettingsDestination(
                        id: hudDestinationID,
                        title: "HUD",
                        iconSystemName: "dial.medium.fill",
                        isAvailable: { true },
                        makeView: { AnyView(HUDSettingsPage()) }
                    )
                ]
            ),
            SettingsCatalogEntry(
                id: cameraFeatureID,
                displayName: "Camera Mirror",
                iconSystemName: "web.camera",
                owner: nil,
                management: .configurationOnly,
                order: cameraOrder,
                destinations: [
                    ExtensionSettingsDestination(
                        id: cameraDestinationID,
                        title: "Camera Mirror",
                        iconSystemName: "web.camera",
                        isAvailable: { true },
                        makeView: { AnyView(CameraMirrorSettingsPage()) }
                    )
                ]
            ),
        ]
    }
}
