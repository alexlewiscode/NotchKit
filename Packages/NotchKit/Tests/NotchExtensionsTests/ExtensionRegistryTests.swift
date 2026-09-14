//
//  ExtensionRegistryTests.swift
//  NotchExtensionsTests
//

import NotchAPI
import NotchExtensions
import XCTest

final class ExtensionRegistryTests: XCTestCase {
    func testRegistersCompatibleDescriptor() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        let destination = TestFactory.destination("com.boringnotch.alpha.open")
        let descriptor = TestFactory.descriptor(
            id: id,
            capabilities: [.openDestination],
            openDestinations: [destination]
        )

        try registry.register(descriptor)

        XCTAssertEqual(registry.descriptors.count, 1)
        XCTAssertEqual(registry.openDestination(for: destination.id)?.id, destination.id)
        XCTAssertEqual(registry.extensionID(forDestination: destination.id), id)
    }

    func testRejectsDuplicateExtensionID() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        try registry.register(TestFactory.descriptor(id: id))

        XCTAssertThrowsError(try registry.register(TestFactory.descriptor(id: id))) { error in
            XCTAssertEqual(error as? ExtensionRegistryError, .duplicateExtensionID(id))
        }
    }

    func testRejectsDuplicateDestinationID() throws {
        let registry = ExtensionRegistry()
        let first = try TestFactory.identity("com.boringnotch.alpha")
        let second = try TestFactory.identity("com.boringnotch.beta")
        let destination = TestFactory.destination("com.boringnotch.shared.open")

        try registry.register(
            TestFactory.descriptor(
                id: first,
                capabilities: [.openDestination],
                openDestinations: [destination]
            )
        )

        XCTAssertThrowsError(
            try registry.register(
                TestFactory.descriptor(
                    id: second,
                    capabilities: [.openDestination],
                    openDestinations: [destination]
                )
            )
        ) { error in
            XCTAssertEqual(error as? ExtensionRegistryError, .duplicateDestinationID(destination.id))
        }
    }

    func testRejectsDuplicateDestinationWithinDescriptor() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        let destination = TestFactory.destination("com.boringnotch.alpha.open")
        let descriptor = TestFactory.descriptor(
            id: id,
            capabilities: [.openDestination],
            openDestinations: [destination, destination]
        )

        XCTAssertThrowsError(try registry.register(descriptor)) { error in
            XCTAssertEqual(error as? ExtensionRegistryError, .duplicateDestinationID(destination.id))
        }
    }

    func testRejectsIncompatibleAPIVersion() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        let incompatible = ExtensionAPIVersion(major: 2, minor: 0, patch: 0)

        XCTAssertThrowsError(
            try registry.register(TestFactory.descriptor(id: id, apiVersion: incompatible))
        ) { error in
            XCTAssertEqual(
                error as? ExtensionRegistryError,
                .incompatibleAPIVersion(id, found: incompatible)
            )
        }
    }

    func testRejectsCapabilityMismatch() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        let destination = TestFactory.destination("com.boringnotch.alpha.open")
        let descriptor = TestFactory.descriptor(
            id: id,
            capabilities: [],
            openDestinations: [destination]
        )

        XCTAssertThrowsError(try registry.register(descriptor)) { error in
            XCTAssertEqual(
                error as? ExtensionRegistryError,
                .capabilityMismatch(id, missing: .openDestination)
            )
        }
    }

    func testOpenDestinationsAreSortedByOrder() throws {
        let registry = ExtensionRegistry()
        let id = try TestFactory.identity("com.boringnotch.alpha")
        let later = TestFactory.destination("com.boringnotch.alpha.b", order: 10)
        let earlier = TestFactory.destination("com.boringnotch.alpha.a", order: 1)

        try registry.register(
            TestFactory.descriptor(
                id: id,
                capabilities: [.openDestination],
                openDestinations: [later, earlier]
            )
        )

        XCTAssertEqual(registry.openDestinations.map(\.id), [earlier.id, later.id])
    }
}