//
//  ExtensionRegistryTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

final class ExtensionRegistryTests: XCTestCase {
    func testRegistersCompatibleDefinition() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        let destination = TestFactory.destination("com.notchkit.alpha.open")

        try registry.register(
            TestFactory.definition(id: id, openDestinations: [destination])
        )

        XCTAssertEqual(registry.definitions.count, 1)
        XCTAssertEqual(registry.metadata(for: id)?.id, id)
        XCTAssertNotNil(registry.definition(for: id))
    }

    func testRejectsDuplicateExtensionID() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id))

        XCTAssertThrowsError(try registry.register(TestFactory.definition(id: id))) { error in
            XCTAssertEqual(error as? ExtensionRegistryError, .duplicateExtensionID(id))
        }
    }

    func testRejectsIncompatibleSDKRange() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")

        XCTAssertThrowsError(
            try registry.register(TestFactory.definition(id: id, sdkRange: ">=2.0.0"))
        ) { error in
            XCTAssertEqual(
                error as? ExtensionRegistryError,
                .incompatibleManifest(
                    .unsupportedSDKVersion(
                        id,
                        required: ExtensionVersionRange.parse(">=2.0.0")!,
                        running: .current
                    )
                )
            )
        }
    }

    func testRejectsUnsupportedArtifactKind() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")

        XCTAssertThrowsError(
            try registry.register(TestFactory.definition(id: id, artifactKind: .appExtension))
        ) { error in
            XCTAssertEqual(
                error as? ExtensionRegistryError,
                .incompatibleManifest(.unsupportedArtifactKind(id, .appExtension))
            )
        }
    }

    func testRegistersMultipleSortedByIdentity() throws {
        let registry = TestFactory.registry()
        let beta = try TestFactory.identity("com.notchkit.beta")
        let alpha = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: beta))
        try registry.register(TestFactory.definition(id: alpha))

        XCTAssertEqual(registry.metadata.map(\.id), [alpha, beta])
    }

    func testRemoveDropsDefinition() throws {
        let registry = TestFactory.registry()
        let id = try TestFactory.identity("com.notchkit.alpha")
        try registry.register(TestFactory.definition(id: id))

        XCTAssertNotNil(registry.remove(id))
        XCTAssertNil(registry.definition(for: id))
    }
}
