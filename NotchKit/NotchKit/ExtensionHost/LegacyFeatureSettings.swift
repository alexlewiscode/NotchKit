//
//  LegacyFeatureSettings.swift
//  NotchKit
//
//  Full extension definitions for the features that are not yet extracted into
//  separate packages: Calendar & Reminders, Media, HUD, and Camera Mirror.
//
//  Each definition declares its configuration pages lifecycle-independently, so
//  configuration stays reachable while the feature is disabled or failed. The
//  pages read configuration only and never activate the feature or request a
//  permission.
//

import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

/// Host-owned extension definitions for not-yet-extracted features.
enum LegacyFeatureSettings {
    static let calendarFeatureID = FeatureSettingsID(BuiltInExtensionIDs.calendar.rawValue)
    static let mediaFeatureID = FeatureSettingsID(BuiltInExtensionIDs.media.rawValue)
    static let hudFeatureID = FeatureSettingsID(BuiltInExtensionIDs.hud.rawValue)
    static let cameraFeatureID = FeatureSettingsID(BuiltInExtensionIDs.camera.rawValue)

    static let calendarDestinationID = BuiltInExtensionIDs.calendarSettings
    static let mediaDestinationID = BuiltInExtensionIDs.mediaSettings
    static let hudDestinationID = BuiltInExtensionIDs.hudSettings
    static let cameraDestinationID = BuiltInExtensionIDs.cameraSettings

    /// Presentation order shared with `NotchKitRuntime`.
    static let calendarOrder = 10
    static let mediaOrder = 30
    static let hudOrder = 40
    static let cameraOrder = 50

    private static var supportedHostVersions: ExtensionVersionRange {
        ExtensionVersionRange(minimum: ExtensionVersion(major: 1, minor: 0, patch: 0))
    }

    private static var supportedSDKVersions: ExtensionVersionRange {
        ExtensionVersionRange(
            minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
            maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
        )
    }

    static func definitions() -> [ExtensionDefinition] {
        [calendarDefinition(), mediaDefinition(), hudDefinition(), cameraDefinition()]
    }

    static func calendarDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.calendar,
                displayName: "Calendar & Reminders",
                summary: "Events and reminders in the notch.",
                iconSystemName: "calendar",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.settingsDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: calendarDestinationID.rawValue,
                        kind: .settingsDestination
                    )
                ],
                defaultEnabled: false
            ),
            settings: {
                [
                    ExtensionSettingsDestination(
                        id: calendarDestinationID,
                        title: "Calendar & Reminders",
                        iconSystemName: "calendar",
                        isAvailable: { true },
                        makeView: { AnyView(CalendarSettingsPage()) }
                    )
                ]
            }
        ) { context in
            CalendarFeature(context: context, manager: .shared)
        }
    }

    static func mediaDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.media,
                displayName: "Media",
                summary: "Now playing, controls, and visualizer.",
                iconSystemName: "play.laptopcomputer",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.settingsDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: mediaDestinationID.rawValue,
                        kind: .settingsDestination
                    )
                ],
                defaultEnabled: true
            ),
            settings: {
                [
                    ExtensionSettingsDestination(
                        id: mediaDestinationID,
                        title: "Media",
                        iconSystemName: "play.laptopcomputer",
                        isAvailable: { true },
                        makeView: { AnyView(MediaSettingsPage()) }
                    )
                ]
            }
        ) { context in
            MediaFeature(context: context, manager: .shared)
        }
    }

    static func hudDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.hud,
                displayName: "HUD",
                summary: "Volume, brightness, and media-key indicators.",
                iconSystemName: "dial.medium.fill",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.settingsDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: hudDestinationID.rawValue,
                        kind: .settingsDestination
                    )
                ],
                defaultEnabled: false
            ),
            settings: {
                [
                    ExtensionSettingsDestination(
                        id: hudDestinationID,
                        title: "HUD",
                        iconSystemName: "dial.medium.fill",
                        isAvailable: { true },
                        makeView: { AnyView(HUDSettingsPage()) }
                    )
                ]
            }
        ) { context in
            HUDFeature(context: context)
        }
    }

    static func cameraDefinition() -> ExtensionDefinition {
        ExtensionDefinition(
            metadata: ExtensionMetadata(
                id: BuiltInExtensionIDs.camera,
                displayName: "Camera Mirror",
                summary: "Webcam preview in the notch.",
                iconSystemName: "web.camera",
                extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
                apiVersion: .current,
                supportedHostVersions: supportedHostVersions,
                supportedSDKVersions: supportedSDKVersions,
                capabilities: [.settingsDestination],
                artifactKind: .compiledIn,
                entryPoints: [
                    ExtensionEntryPoint(
                        id: cameraDestinationID.rawValue,
                        kind: .settingsDestination
                    )
                ],
                defaultEnabled: false
            ),
            settings: {
                [
                    ExtensionSettingsDestination(
                        id: cameraDestinationID,
                        title: "Camera Mirror",
                        iconSystemName: "web.camera",
                        isAvailable: { true },
                        makeView: { AnyView(CameraMirrorSettingsPage()) }
                    )
                ]
            }
        ) { context in
            CameraFeature(context: context, manager: .shared)
        }
    }
}
