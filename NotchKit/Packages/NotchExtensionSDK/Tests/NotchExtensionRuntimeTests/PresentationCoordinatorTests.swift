//
//  PresentationCoordinatorTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class PresentationCoordinatorTests: XCTestCase {
    private func makeHarness() throws -> (
        coordinator: PresentationCoordinator,
        home: DestinationID,
        shelf: DestinationID
    ) {
        let registry = TestFactory.registry()
        let home = try TestFactory.identity("com.notchkit.home")
        let shelf = try TestFactory.identity("com.notchkit.shelf")
        let homeDestination = TestFactory.destination("com.notchkit.destination.home", title: "Home")
        let shelfDestination = TestFactory.destination("com.notchkit.destination.shelf", title: "Shelf")
        try registry.register(TestFactory.definition(id: home, openDestinations: [homeDestination]))
        try registry.register(TestFactory.definition(id: shelf, openDestinations: [shelfDestination]))

        let contributions = ContributionStore()
        try contributions.set(open: [homeDestination], closed: [], settings: [], for: home)
        try contributions.set(open: [shelfDestination], closed: [], settings: [], for: shelf)

        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        manager.reconcile()

        let coordinator = PresentationCoordinator(
            contributions: contributions, manager: manager, homeID: homeDestination.id
        )
        return (coordinator, homeDestination.id, shelfDestination.id)
    }

    func testRoutersAreIndependentPerDisplay() throws {
        let harness = try makeHarness()
        let displayA = DisplayID("A")
        let displayB = DisplayID("B")

        harness.coordinator.router(for: displayA).select(harness.shelf)

        XCTAssertEqual(
            harness.coordinator.router(for: displayA).activeDestinationID, harness.shelf
        )
        XCTAssertEqual(
            harness.coordinator.router(for: displayB).activeDestinationID, harness.home
        )
    }

    func testRouterForSameDisplayIsStable() throws {
        let harness = try makeHarness()
        let display = DisplayID("A")
        let first = harness.coordinator.router(for: display)
        let second = harness.coordinator.router(for: display)
        XCTAssertTrue(first === second)
    }

    func testRefreshAllBumpsRevision() throws {
        let harness = try makeHarness()
        _ = harness.coordinator.router(for: DisplayID("A"))
        let before = harness.coordinator.revision
        harness.coordinator.refreshAll()
        XCTAssertGreaterThan(harness.coordinator.revision, before)
    }

    func testRemoveRouter() throws {
        let harness = try makeHarness()
        let display = DisplayID("A")
        _ = harness.coordinator.router(for: display)
        XCTAssertEqual(harness.coordinator.displayIDs, [display])

        harness.coordinator.removeRouter(for: display)
        XCTAssertTrue(harness.coordinator.displayIDs.isEmpty)
    }
}