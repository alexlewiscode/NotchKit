//
//  TestFactory.swift
//  NotchExtensionRuntimeTests
//

import Foundation
import NotchExtensionSDK
import SwiftUI

enum TestFactory {
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

    static func descriptor(
        id: ExtensionIdentity,
        apiVersion: ExtensionAPIVersion = .current,
        defaultEnabled: Bool = true,
        capabilities: Set<ExtensionCapability> = [],
        openDestinations: [NotchOpenDestination] = [],
        closedNotchContributions: [ClosedNotchContribution] = [],
        settingsDestinations: [ExtensionSettingsDestination] = []
    ) -> ExtensionDescriptor {
        ExtensionDescriptor(
            id: id,
            displayName: id.rawValue,
            iconSystemName: "square",
            apiVersion: apiVersion,
            capabilities: capabilities,
            defaultEnabled: defaultEnabled,
            openDestinations: openDestinations,
            closedNotchContributions: closedNotchContributions,
            settingsDestinations: settingsDestinations
        )
    }
}