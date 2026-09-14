//
//  TestFactory.swift
//  NotchExtensionRuntimeTests
//

import Foundation
import NotchExtensionSDK
import NotchExtensionRuntime
import SwiftUI

enum TestFactory {
    static let hostVersion = ExtensionVersion(major: 2, minor: 0, patch: 0)

    static func identity(_ raw: String) throws -> ExtensionIdentity {
        try ExtensionIdentity(raw)
    }

    static func destination(
        _ raw: String,
        title: String = "Destination",
        order: Int = 0,
        available: @escaping () -> Bool = { true }
    ) -> NotchOpenDestination {
        NotchOpenDestination(
            id: DestinationID(raw),
            title: title,
            iconSystemName: "square",
            order: order,
            isAvailable: available,
            makeView: { AnyView(EmptyView()) }
        )
    }

    static func settingsDestination(
        _ raw: String,
        title: String = "Settings",
        available: @escaping () -> Bool = { true }
    ) -> ExtensionSettingsDestination {
        ExtensionSettingsDestination(
            id: DestinationID(raw),
            title: title,
            iconSystemName: "gearshape",
            isAvailable: available,
            makeView: { AnyView(EmptyView()) }
        )
    }

    static func contribution(
        _ raw: String,
        extensionID: ExtensionIdentity,
        region: ClosedNotchRegion = .exclusion,
        priority: Int = 0,
        tieBreaker: String = "a",
        available: @escaping (ClosedNotchRenderSnapshot) -> Bool = { _ in true }
    ) -> ClosedNotchContribution {
        ClosedNotchContribution(
            id: ContributionID(raw),
            extensionID: extensionID,
            region: region,
            priority: priority,
            tieBreaker: tieBreaker,
            isAvailable: available,
            makeView: { AnyView(EmptyView()) }
        )
    }

    /// Entry points derived from contributions, one per contributed id.
    static func entryPoints(
        openDestinations: [NotchOpenDestination],
        closedNotchContributions: [ClosedNotchContribution],
        settingsDestinations: [ExtensionSettingsDestination]
    ) -> [ExtensionEntryPoint] {
        openDestinations.map { ExtensionEntryPoint(id: $0.id.rawValue, kind: .openDestination) }
            + closedNotchContributions.map {
                ExtensionEntryPoint(id: $0.id.rawValue, kind: .closedNotchContribution)
            }
            + settingsDestinations.map {
                ExtensionEntryPoint(id: $0.id.rawValue, kind: .settingsDestination)
            }
    }

    static func metadata(
        id: ExtensionIdentity,
        defaultEnabled: Bool = true,
        artifactKind: ExtensionArtifactKind = .compiledIn,
        hostRange: String = ">=1.0.0",
        sdkRange: String = ">=1.0.0 <2.0.0",
        capabilities: Set<ExtensionCapability>? = nil,
        entryPoints: [ExtensionEntryPoint]? = nil
    ) -> ExtensionMetadata {
        let resolvedEntryPoints = entryPoints ?? []
        let resolvedCapabilities = capabilities
            ?? Set(resolvedEntryPoints.map { $0.kind.requiredCapability })
        return ExtensionMetadata(
            id: id,
            displayName: id.rawValue,
            iconSystemName: "square",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            apiVersion: ExtensionAPIVersion(major: 1, minor: 0, patch: 0),
            supportedHostVersions: ExtensionVersionRange.parse(hostRange)!,
            supportedSDKVersions: ExtensionVersionRange.parse(sdkRange)!,
            capabilities: resolvedCapabilities,
            artifactKind: artifactKind,
            entryPoints: resolvedEntryPoints,
            defaultEnabled: defaultEnabled
        )
    }

    static func definition(
        id: ExtensionIdentity,
        defaultEnabled: Bool = true,
        artifactKind: ExtensionArtifactKind = .compiledIn,
        hostRange: String = ">=1.0.0",
        sdkRange: String = ">=1.0.0 <2.0.0",
        capabilities: Set<ExtensionCapability>? = nil,
        entryPoints: [ExtensionEntryPoint]? = nil,
        openDestinations: [NotchOpenDestination] = [],
        closedNotchContributions: [ClosedNotchContribution] = [],
        settingsDestinations: [ExtensionSettingsDestination] = []
    ) -> ExtensionDefinition {
        let derivedEntryPoints = entryPoints ?? Self.entryPoints(
            openDestinations: openDestinations,
            closedNotchContributions: closedNotchContributions,
            settingsDestinations: settingsDestinations
        )
        let derivedCapabilities = capabilities
            ?? Set(derivedEntryPoints.map { $0.kind.requiredCapability })
        let metadata = ExtensionMetadata(
            id: id,
            displayName: id.rawValue,
            iconSystemName: "square",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            apiVersion: ExtensionAPIVersion(major: 1, minor: 0, patch: 0),
            supportedHostVersions: ExtensionVersionRange.parse(hostRange)!,
            supportedSDKVersions: ExtensionVersionRange.parse(sdkRange)!,
            capabilities: derivedCapabilities,
            artifactKind: artifactKind,
            entryPoints: derivedEntryPoints,
            defaultEnabled: defaultEnabled
        )
        return ExtensionDefinition(metadata: metadata) { context in
            StaticExtension(
                open: openDestinations,
                closed: closedNotchContributions,
                settings: settingsDestinations
            )
        }
    }

    static func registry() -> ExtensionRegistry {
        ExtensionRegistry(hostVersion: hostVersion)
    }
}
