//
//  NotchRouterTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class NotchRouterTests: XCTestCase {
    private func makeContext(
        includeShelf: Bool = true,
        shelfAvailable: @escaping () -> Bool = { true },
        shelfEnabled: Bool = true
    ) throws -> (
        router: NotchRouter,
        home: DestinationID,
        shelf: DestinationID,
        manager: ExtensionManager,
        contributions: ContributionStore
    ) {
        let registry = TestFactory.registry()
        let home = try TestFactory.identity("com.notchkit.home")
        let homeDestination = TestFactory.destination("com.notchkit.destination.home", title: "Home")
        try registry.register(TestFactory.definition(id: home, openDestinations: [homeDestination]))

        let contributions = ContributionStore()
        try contributions.set(open: [homeDestination], closed: [], settings: [], for: home)

        let shelfDestination = TestFactory.destination(
            "com.notchkit.destination.shelf", title: "Shelf", available: shelfAvailable
        )
        if includeShelf {
            let shelf = try TestFactory.identity("com.notchkit.shelf")
            try registry.register(
                TestFactory.definition(
                    id: shelf, defaultEnabled: shelfEnabled, openDestinations: [shelfDestination]
                )
            )
            try contributions.set(open: [shelfDestination], closed: [], settings: [], for: shelf)
        }

        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        manager.reconcile()

        let router = NotchRouter(
            displayID: DisplayID("test-display"),
            homeID: homeDestination.id,
            contributions: contributions,
            manager: manager
        )
        return (router, homeDestination.id, shelfDestination.id, manager, contributions)
    }

    func testDefaultsToHome() throws {
        let context = try makeContext()
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testSelectsShelfWhenAvailable() throws {
        let context = try makeContext()
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.shelf)
    }

    func testFallsBackToHomeWhenDestinationMissing() throws {
        let context = try makeContext(includeShelf: false)
        context.router.select(DestinationID("com.notchkit.destination.missing"))
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testFallsBackToHomeWhenDestinationUnavailable() throws {
        let context = try makeContext(shelfAvailable: { false })
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testFallsBackToHomeWhenExtensionDisabled() throws {
        let context = try makeContext()
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.shelf)

        let shelfID = try TestFactory.identity("com.notchkit.shelf")
        context.manager.setEnabled(false, for: shelfID)
        context.router.refreshAvailability()
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testAvailableDestinationsExcludeDisabled() throws {
        let context = try makeContext()
        XCTAssertEqual(context.router.availableDestinations.map(\.id), [context.home, context.shelf])

        let shelfID = try TestFactory.identity("com.notchkit.shelf")
        context.manager.setEnabled(false, for: shelfID)
        XCTAssertEqual(context.router.availableDestinations.map(\.id), [context.home])
    }
}