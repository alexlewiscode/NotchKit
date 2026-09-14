//
//  ExtensionCompatibilityTests.swift
//  NotchExtensionRuntimeTests
//
//  Compatibility checks beyond major-version matching.
//

import XCTest
import NotchExtensionSDK

final class ExtensionCompatibilityTests: XCTestCase {
    private func metadata(
        id: String = "com.notchkit.test",
        artifactKind: ExtensionArtifactKind = .compiledIn,
        hostRange: String = ">=1.0.0",
        sdkRange: String = ">=1.0.0 <2.0.0",
        capabilities: Set<ExtensionCapability> = [],
        entryPoints: [ExtensionEntryPoint] = []
    ) throws -> ExtensionMetadata {
        ExtensionMetadata(
            id: try ExtensionIdentity(id),
            displayName: "Test",
            iconSystemName: "gear",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            apiVersion: ExtensionAPIVersion(major: 1, minor: 0, patch: 0),
            supportedHostVersions: ExtensionVersionRange.parse(hostRange)!,
            supportedSDKVersions: ExtensionVersionRange.parse(sdkRange)!,
            capabilities: capabilities,
            artifactKind: artifactKind,
            entryPoints: entryPoints,
            defaultEnabled: false
        )
    }

    private let hostVersion = ExtensionVersion(major: 2, minor: 5, patch: 0)

    func testAcceptsCompatibleManifest() throws {
        let manifest = try metadata(
            capabilities: [.openDestination],
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)]
        )
        XCTAssertNoThrow(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        )
    }

    func testRejectsUnsupportedArtifactKind() throws {
        let manifest = try metadata(artifactKind: .appExtension)
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            XCTAssertEqual(
                error as? ExtensionCompatibilityError,
                .unsupportedArtifactKind(manifest.id, .appExtension)
            )
        }
    }

    func testRejectsHostVersionOutsideRange() throws {
        let manifest = try metadata(hostRange: ">=3.0.0")
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            guard case .unsupportedHostVersion = error as? ExtensionCompatibilityError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testExclusiveHostUpperBound() throws {
        let manifest = try metadata(hostRange: ">=1.0.0 <2.5.0")
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        )
    }

    func testRejectsSDKVersionOutsideRange() throws {
        let manifest = try metadata(sdkRange: ">=2.0.0")
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            guard case .unsupportedSDKVersion = error as? ExtensionCompatibilityError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRejectsUndeclaredCapability() throws {
        let manifest = try metadata(
            capabilities: [],
            entryPoints: [ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)]
        )
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            XCTAssertEqual(
                error as? ExtensionCompatibilityError,
                .undeclaredCapability(manifest.id, .openDestination)
            )
        }
    }

    func testRejectsCapabilityWithoutEntryPoint() throws {
        let manifest = try metadata(capabilities: [.settingsDestination])
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            XCTAssertEqual(
                error as? ExtensionCompatibilityError,
                .capabilityWithoutEntryPoint(manifest.id, .settingsDestination)
            )
        }
    }

    func testRejectsDuplicateEntryPoint() throws {
        let manifest = try metadata(
            capabilities: [.openDestination],
            entryPoints: [
                ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination),
                ExtensionEntryPoint(id: "com.notchkit.test.page", kind: .openDestination)
            ]
        )
        XCTAssertThrowsError(
            try ExtensionCompatibility.validate(manifest, hostVersion: hostVersion)
        ) { error in
            XCTAssertEqual(
                error as? ExtensionCompatibilityError,
                .duplicateEntryPoint(manifest.id, id: "com.notchkit.test.page")
            )
        }
    }
}
