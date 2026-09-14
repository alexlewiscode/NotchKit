//
//  NotchRouterTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

@MainActor
final class NotchRouterTests: XCTestCase {
    private func makeRouter(
        includeShelf: Bool = true,
        shelfAvailable: @escaping () -> Bool = { true },
        shelfEnabled: Bool = true
    ) throws -> (router: NotchRouter, home: DestinationID, shelf: DestinationID, manager: ExtensionManager, registry: ExtensionRegistry) {
        let registry = ExtensionRegistry()
        let home = try TestFactory.identity("com.boringnotch.home")
        let homeDestination = TestFactory.destination("com.boringnotch.destination.home", title: "Home")
        try registry.register(
            TestFactory.descriptor(
                id: home,
                capabilities: [.openDestination],
                openDestinations: [homeDestination]
            )
        )

        let shelfDestination = TestFactory.destination(
            "com.boringnotch.destination.shelf", title: "Shelf", available: shelfAvailable
        )
        if includeShelf {
            let shelf = try TestFactory.identity("com.boringnotch.shelf")
            try registry.register(
                TestFactory.descriptor(
                    id: shelf,
                    defaultEnabled: shelfEnabled,
                    capabilities: [.openDestination],
                    openDestinations: [shelfDestination]
                )
            )
        }

        let manager = ExtensionManager(registry: registry, store: InMemoryExtensionStateStore())
        manager.reconcile()
        let router = NotchRouter(
            registry: registry,
            manager: manager,
            homeID: homeDestination.id
        )
        return (router, homeDestination.id, shelfDestination.id, manager, registry)
    }

    func testDefaultsToHome() throws {
        let context = try makeRouter()
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testSelectsShelfWhenAvailable() throws {
        let context = try makeRouter()
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.shelf)
    }

    func testFallsBackToHomeWhenDestinationMissing() throws {
        let context = try makeRouter(includeShelf: false)
        context.router.select(DestinationID("com.boringnotch.destination.missing"))
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testFallsBackToHomeWhenDestinationUnavailable() throws {
        let context = try makeRouter(shelfAvailable: { false })
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testFallsBackToHomeWhenExtensionDisabled() throws {
        let context = try makeRouter()
        context.router.select(context.shelf)
        XCTAssertEqual(context.router.activeDestinationID, context.shelf)

        let shelfID = try TestFactory.identity("com.boringnotch.shelf")
        context.manager.setEnabled(false, for: shelfID)
        context.router.refreshAvailability()
        XCTAssertEqual(context.router.activeDestinationID, context.home)
    }

    func testAvailableDestinationsExcludeDisabled() throws {
        let context = try makeRouter()
        XCTAssertEqual(context.router.availableDestinations.map(\.id), [context.home, context.shelf])

        let shelfID = try TestFactory.identity("com.boringnotch.shelf")
        context.manager.setEnabled(false, for: shelfID)
        XCTAssertEqual(context.router.availableDestinations.map(\.id), [context.home])
    }
}