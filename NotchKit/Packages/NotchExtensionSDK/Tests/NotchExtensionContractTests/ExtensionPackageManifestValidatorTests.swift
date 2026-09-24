import Foundation
import NotchExtensionSDK
import XCTest

final class ExtensionPackageManifestValidatorTests: XCTestCase {
    func testAcceptsValidManifestAndPermissionDisclosure() throws {
        let manifest = try manifest()
        let permission = try XCTUnwrap(manifest.permissions.first)
        XCTAssertEqual(permission.kind, .camera)
        XCTAssertTrue(permission.required)
        XCTAssertEqual(permission.owner, .extension)
        XCTAssertEqual(permission.usageDescriptionKey, "CameraUsageDescription")
        XCTAssertNoThrow(try ExtensionPackageManifestValidator.validate(manifest))
    }

    func testRejectsWrongSchemaArtifactKindAndSource() throws {
        assertError(try manifest { $0["schemaVersion"] = 1 }, .unsupportedSchemaVersion(1))
        assertError(
            try manifest { root in Self.object(&root, "metadata")["artifactKind"] = "xpc-service" },
            .artifactKindMismatch
        )
        assertError(
            try manifest { root in Self.object(&root, "metadata")["source"] = "firstParty" },
            .invalidSource(.firstParty)
        )
    }

    func testMarketplaceSourceRequiresMarketplaceValidationContext() throws {
        let marketplace = try manifest { root in
            Self.object(&root, "metadata")["source"] = "marketplace"
        }

        assertError(
            marketplace,
            .invalidSource(.marketplace)
        )
        XCTAssertNoThrow(
            try ExtensionPackageManifestValidator.validate(marketplace, context: .marketplace)
        )
    }

    func testRequiresAppExtensionMetadataOnlyForAppExtensions() throws {
        assertError(
            try manifest { root in Self.object(&root, "artifact").removeObject(forKey: "appExtension") },
            .missingAppExtensionMetadata
        )
        assertError(
            try manifest { root in
                Self.object(&root, "artifact")["kind"] = "xpc-service"
                Self.object(&root, "metadata")["artifactKind"] = "xpc-service"
            },
            .unexpectedAppExtensionMetadata
        )
    }

    func testRequiresMacOS26AndValidIdentifiers() throws {
        assertError(
            try manifest { root in Self.appExtension(&root)["minimumMacOSVersion"] = "25.9.0" },
            .unsupportedMinimumMacOSVersion(ExtensionVersion(major: 25, minor: 9, patch: 0))
        )
        assertError(
            try manifest { root in Self.appExtension(&root)["providerBundleIdentifier"] = "not valid" },
            .invalidIdentifier(field: "provider bundle identifier", value: "not valid")
        )
        assertError(
            try manifest { root in Self.appExtension(&root)["extensionPointIdentifier"] = " " },
            .invalidIdentifier(field: "extension-point identifier", value: " ")
        )
    }

    func testRequiresDistinctNestedBundleIdentifiers() throws {
        assertError(
            try manifest { root in
                Self.appExtension(&root)["extensionBundleIdentifier"] = "com.notchkit.tests.provider"
            },
            .matchingBundleIdentifiers
        )
        assertError(
            try manifest { root in
                Self.appExtension(&root)["extensionBundleIdentifier"] = "com.other.extension"
            },
            .extensionIsNotContainedByProvider
        )
    }

    func testRequiresPositiveOrderedProtocolRangeAndArchitectures() throws {
        assertError(
            try manifest { root in
                let artifact = Self.appExtension(&root)
                Self.object(artifact, "protocolVersions")["minimum"] = 0
            },
            .invalidProtocolVersionRange
        )
        assertError(
            try manifest { root in
                let artifact = Self.appExtension(&root)
                let range = Self.object(artifact, "protocolVersions")
                range["minimum"] = 3
                range["maximum"] = 2
            },
            .invalidProtocolVersionRange
        )
        assertError(
            try manifest { root in Self.appExtension(&root)["architectures"] = [] },
            .noArchitectures
        )
    }

    func testRequiresNonemptyOneToOneEntryPoints() throws {
        assertError(try manifest { $0["entryPoints"] = [] }, .noEntryPoints)
        assertError(
            try manifest { root in
                var entries = root["entryPoints"] as! [[String: Any]]
                var descriptor = entries[0]
                var entry = descriptor["entryPoint"] as! [String: Any]
                entry["id"] = "other"
                descriptor["entryPoint"] = entry
                entries[0] = descriptor
                root["entryPoints"] = entries
            },
            .entryPointMismatch("other")
        )
    }

    func testRejectsDuplicateMetadataAndPackageEntryPointIDs() throws {
        assertError(
            try manifest { root in
                let metadata = Self.object(&root, "metadata")
                var entries = metadata["entryPoints"] as! [[String: Any]]
                entries.append(entries[0])
                metadata["entryPoints"] = entries
            },
            .duplicateMetadataEntryPoint("main")
        )
        assertError(
            try manifest { root in
                var entries = root["entryPoints"] as! [[String: Any]]
                entries.append(entries[0])
                root["entryPoints"] = entries
            },
            .duplicatePackageEntryPoint("main")
        )
    }

    func testEnforcesPresentationRules() throws {
        assertError(
            try manifest { root in
                var entries = root["entryPoints"] as! [[String: Any]]
                entries[0].removeValue(forKey: "sceneName")
                root["entryPoints"] = entries
            },
            .missingRemoteScene("main")
        )
        assertError(
            try manifest { root in
                var entries = root["entryPoints"] as! [[String: Any]]
                entries[0]["presentationMode"] = "declarative"
                root["entryPoints"] = entries
            },
            .unexpectedDeclarativeScene("main")
        )
    }

    func testRejectsEmptyAndDuplicatePermissionDisclosures() throws {
        assertError(
            try manifest { root in
                var permissions = root["permissions"] as! [[String: Any]]
                permissions[0]["usageDescriptionKey"] = "  "
                root["permissions"] = permissions
            },
            .emptyPermissionUsageDescriptionKey(.camera)
        )
        assertError(
            try manifest { root in
                var permissions = root["permissions"] as! [[String: Any]]
                var duplicate = permissions[0]
                duplicate["required"] = false
                permissions.append(duplicate)
                root["permissions"] = permissions
            },
            .duplicatePermission(.camera)
        )
    }

    func testEnforcesPracticalHostActionConsistency() throws {
        assertError(
            try manifest { root in
                root["hostActions"] = ["close-notch"]
                let metadata = Self.object(&root, "metadata")
                var metadataEntries = metadata["entryPoints"] as! [[String: Any]]
                metadataEntries[0]["kind"] = "settings-destination"
                metadata["entryPoints"] = metadataEntries
                var packageEntries = root["entryPoints"] as! [[String: Any]]
                var entry = packageEntries[0]["entryPoint"] as! [String: Any]
                entry["kind"] = "settings-destination"
                packageEntries[0]["entryPoint"] = entry
                root["entryPoints"] = packageEntries
            },
            .hostActionRequiresOpenDestination(.closeNotch)
        )
        assertError(
            try manifest { $0["hostActions"] = ["show-sneak-peek"] },
            .incompleteSneakPeekActions
        )
    }

    private func manifest(
        mutate: ((inout [String: Any]) -> Void)? = nil
    ) throws -> ExtensionPackageManifest {
        let metadata = ExtensionMetadata(
            id: try ExtensionIdentity("com.notchkit.tests.extension"),
            displayName: "Validator Test",
            iconSystemName: "puzzlepiece.extension",
            extensionVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            supportedHostVersions: ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 0, patch: 0)
            ),
            supportedSDKVersions: ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 2, patch: 0),
                maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
            ),
            capabilities: [.openDestination],
            artifactKind: .appExtension,
            entryPoints: [.init(id: "main", kind: .openDestination)],
            defaultEnabled: false,
            source: .localDeveloper
        )
        let original = ExtensionPackageManifest(
            metadata: metadata,
            artifact: .init(
                kind: .appExtension,
                appExtension: .init(
                    providerBundleIdentifier: "com.notchkit.tests.provider",
                    extensionBundleIdentifier: "com.notchkit.tests.provider.extension",
                    extensionPointIdentifier: "com.notchkit.extension-point",
                    minimumMacOSVersion: ExtensionVersion(major: 26, minor: 0, patch: 0),
                    protocolVersions: .init(minimum: 1, maximum: 2),
                    architectures: [.arm64]
                )
            ),
            permissions: [.camera(usageDescriptionKey: "CameraUsageDescription")],
            hostActions: [.openDestination],
            entryPoints: [
                .init(entryPoint: metadata.entryPoints[0], presentationMode: .remoteScene, sceneName: "main")
            ]
        )
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        mutate?(&object)
        return try JSONDecoder().decode(
            ExtensionPackageManifest.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private static func object(_ root: inout [String: Any], _ key: String) -> NSMutableDictionary {
        let value = NSMutableDictionary(dictionary: root[key] as! [String: Any])
        root[key] = value
        return value
    }

    private static func appExtension(_ root: inout [String: Any]) -> NSMutableDictionary {
        let artifact = object(&root, "artifact")
        let value = NSMutableDictionary(dictionary: artifact["appExtension"] as! [String: Any])
        artifact["appExtension"] = value
        return value
    }

    private static func object(_ root: NSMutableDictionary, _ key: String) -> NSMutableDictionary {
        let value = NSMutableDictionary(dictionary: root[key] as! [String: Any])
        root[key] = value
        return value
    }

    private func assertError(
        _ manifest: ExtensionPackageManifest,
        _ expected: ExtensionPackageManifestValidationError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try ExtensionPackageManifestValidator.validate(manifest),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? ExtensionPackageManifestValidationError, expected, file: file, line: line)
        }
    }
}
