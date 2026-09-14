//
//  ContributionStoreTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class ContributionStoreTests: XCTestCase {
    func testSetAndReadContributions() throws {
        let store = ContributionStore()
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open", title: "Alpha")
        let settings = TestFactory.settingsDestination("com.notchkit.alpha.settings")
        let contribution = TestFactory.contribution("com.notchkit.alpha.closed", extensionID: id)

        try store.set(
            open: [destination], closed: [contribution], settings: [settings], for: id
        )

        XCTAssertEqual(store.openDestinations.map(\.id), [destination.id])
        XCTAssertEqual(store.settingsDestinations.map(\.id), [settings.id])
        XCTAssertEqual(store.closedNotchContributions.map(\.id), [contribution.id])
        XCTAssertEqual(store.extensionID(forDestination: destination.id), id)
        XCTAssertEqual(store.extensionID(forSettingsDestination: settings.id), id)
        XCTAssertEqual(store.extensionID(forContribution: contribution.id), id)
    }

    func testOpenDestinationsSortedByOrderThenTitleThenID() throws {
        let store = ContributionStore()
        let id = try TestFactory.identity("com.notchkit.alpha")
        let later = TestFactory.destination("com.notchkit.alpha.c", title: "C", order: 5)
        let earlier = TestFactory.destination("com.notchkit.alpha.a", title: "A", order: 1)
        let sameOrderB = TestFactory.destination("com.notchkit.alpha.b", title: "B", order: 5)

        try store.set(open: [later, earlier, sameOrderB], closed: [], settings: [], for: id)

        XCTAssertEqual(store.openDestinations.map(\.id), [earlier.id, sameOrderB.id, later.id])
    }

    func testRejectsDuplicateDestinationAcrossExtensions() throws {
        let store = ContributionStore()
        let first = try TestFactory.identity("com.notchkit.alpha")
        let second = try TestFactory.identity("com.notchkit.beta")
        let destination = TestFactory.destination("com.notchkit.shared.open")

        try store.set(open: [destination], closed: [], settings: [], for: first)

        XCTAssertThrowsError(
            try store.set(open: [destination], closed: [], settings: [], for: second)
        ) { error in
            XCTAssertEqual(
                error as? ContributionStoreError, .duplicateDestinationID(destination.id)
            )
        }
    }

    func testRejectsDuplicateDestinationWithinSet() throws {
        let store = ContributionStore()
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")

        XCTAssertThrowsError(
            try store.set(open: [destination, destination], closed: [], settings: [], for: id)
        ) { error in
            XCTAssertEqual(
                error as? ContributionStoreError, .duplicateDestinationID(destination.id)
            )
        }
    }

    func testRemoveContributionsClearsAllIndices() throws {
        let store = ContributionStore()
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")
        let contribution = TestFactory.contribution("com.notchkit.alpha.closed", extensionID: id)

        try store.set(open: [destination], closed: [contribution], settings: [], for: id)
        store.removeContributions(for: id)

        XCTAssertTrue(store.openDestinations.isEmpty)
        XCTAssertTrue(store.closedNotchContributions.isEmpty)
        XCTAssertNil(store.extensionID(forDestination: destination.id))
        XCTAssertNil(store.extensionID(forContribution: contribution.id))
    }
}