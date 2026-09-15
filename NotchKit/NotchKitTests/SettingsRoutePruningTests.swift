//
//  SettingsRoutePruningTests.swift
//  NotchKitTests
//
//  The Extensions hub keeps a navigation path of typed routes. When a feature's
//  destination disappears from the catalog, those routes must be pruned so the
//  hub never navigates to a feature that no longer exists.
//

import NotchExtensionRuntime
import NotchExtensionSDK
import SwiftUI
import XCTest
@testable import NotchKit

@MainActor
final class SettingsRoutePruningTests: XCTestCase {

    private func destination(_ raw: String) -> ExtensionSettingsDestination {
        ExtensionSettingsDestination(
            id: DestinationID(raw),
            title: raw,
            iconSystemName: "square",
            isAvailable: { true },
            makeView: { AnyView(EmptyView()) }
        )
    }

    private func entry(
        _ raw: String,
        destination: ExtensionSettingsDestination,
        order: Int
    ) -> SettingsCatalogEntry {
        SettingsCatalogEntry(
            id: FeatureSettingsID(raw),
            displayName: raw,
            iconSystemName: "square",
            owner: nil,
            management: .configurationOnly,
            order: order,
            destinations: [destination]
        )
    }

    func testPruningRemovesRoutesForRemovedDestinations() {
        let catalog = SettingsCatalog()
        let alphaDestination = destination("com.notchkit.settings.alpha")
        let betaDestination = destination("com.notchkit.settings.beta")
        let alpha = entry("com.notchkit.feature.alpha", destination: alphaDestination, order: 0)
        let beta = entry("com.notchkit.feature.beta", destination: betaDestination, order: 1)

        catalog.rebuild(from: [], adapters: [alpha, beta])
        let path = [
            ExtensionSettingsRoute(featureID: alpha.id, destinationID: alphaDestination.id),
            ExtensionSettingsRoute(featureID: beta.id, destinationID: betaDestination.id),
        ]

        XCTAssertEqual(catalog.prune(path), path, "Routes present in the catalog are kept")

        let revisionBeforeRemoval = catalog.revision
        catalog.rebuild(from: [], adapters: [beta])

        XCTAssertNotEqual(
            catalog.revision,
            revisionBeforeRemoval,
            "A rebuild that removes a destination must bump the revision so the hub prunes"
        )
        XCTAssertNil(catalog.entry(for: alphaDestination.id))
        XCTAssertNil(catalog.destination(for: alphaDestination.id))
        XCTAssertFalse(catalog.isPresent(alphaDestination.id))
        XCTAssertTrue(catalog.isPresent(betaDestination.id))
        XCTAssertEqual(
            catalog.prune(path),
            [path[1]],
            "Only the removed feature's route is pruned"
        )
    }
}