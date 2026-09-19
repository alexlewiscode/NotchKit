import Foundation
import NotchExtensionSDK
import XCTest

final class ManifestContractTests: XCTestCase {
    func testCurrentAPIVersionIsOneTwo() {
        XCTAssertEqual(ExtensionAPIVersion.current, ExtensionAPIVersion(major: 1, minor: 2, patch: 0))
    }

    func testPackageManifestDefaultsToSchemaVersionTwo() throws {
        let manifest = makeManifest()
        XCTAssertEqual(manifest.schemaVersion, 2)
        XCTAssertEqual(manifest.metadata.id.rawValue, "com.notchkit.tests.extension")
        XCTAssertEqual(manifest.artifact.kind, .appExtension)
        XCTAssertEqual(Set(manifest.permissions.map(\.kind)), [.camera, .mediaControl])
        XCTAssertEqual(manifest.hostActions, [.openDestination])
    }

    func testPackageManifestRoundTrips() throws {
        let original = makeManifest()
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ExtensionPackageManifest.self, from: data), original)
        XCTAssertNoThrow(try ExtensionPackageManifestValidator.validate(original))
    }

    func testAppExtensionArtifactCarriesDiscoveryAndCompatibilityMetadata() throws {
        let artifact = try XCTUnwrap(makeManifest().artifact.appExtension)
        XCTAssertEqual(artifact.providerBundleIdentifier, "com.notchkit.tests.provider")
        XCTAssertEqual(artifact.extensionBundleIdentifier, "com.notchkit.tests.provider.extension")
        XCTAssertEqual(artifact.extensionPointIdentifier, "com.notchkit.extension-point")
        XCTAssertEqual(artifact.minimumMacOSVersion, ExtensionVersion(major: 26, minor: 0, patch: 0))
        XCTAssertEqual(artifact.architectures, [.arm64, .x86_64])
        XCTAssertTrue(artifact.protocolVersions.contains(2))
        XCTAssertFalse(artifact.protocolVersions.contains(4))
    }

    func testPackageEntryPointKeepsPresentationOutsideTierAEntryPoint() {
        let descriptor = makeManifest().entryPoints[0]
        XCTAssertEqual(descriptor.id, "main")
        XCTAssertEqual(descriptor.presentationMode, .remoteScene)
        XCTAssertEqual(descriptor.sceneName, "main")
        XCTAssertNil(descriptor.entryPoint.sceneName)
    }

    func testTierAEntryPointEncodingRemainsUnchanged() throws {
        let entryPoint = ExtensionEntryPoint(id: "main", kind: .openDestination)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(entryPoint)) as? [String: Any]
        )
        XCTAssertEqual(object.count, 2)
        XCTAssertEqual(object["id"] as? String, "main")
        XCTAssertEqual(object["kind"] as? String, "open-destination")
    }

    func testLocalDeveloperSourceRoundTrips() throws {
        let data = try JSONEncoder().encode(ExtensionSource.localDeveloper)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "\"localDeveloper\"")
        XCTAssertEqual(try JSONDecoder().decode(ExtensionSource.self, from: data), .localDeveloper)
    }

    func testFiniteDeclarationEnumsExposeEverySupportedValue() {
        XCTAssertEqual(ExtensionDeclaredPermission.Kind.allCases.count, 4)
        XCTAssertEqual(ExtensionDeclaredPermission.Owner.allCases, [.host, .extension])
        XCTAssertEqual(ExtensionHostAction.allCases.count, 4)
        XCTAssertEqual(ExtensionEntryPointPresentationMode.allCases, [.remoteScene, .declarative])
        XCTAssertEqual(ExtensionArchitecture.allCases, [.arm64, .x86_64])
    }

    private func makeManifest() -> ExtensionPackageManifest {
        let identity = try! ExtensionIdentity("com.notchkit.tests.extension")
        let metadata = ExtensionMetadata(
            id: identity,
            displayName: "Contract Test",
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
            entryPoints: [ExtensionEntryPoint(id: "main", kind: .openDestination)],
            defaultEnabled: false,
            source: .localDeveloper
        )
        let appExtension = AppExtensionArtifactMetadata(
            providerBundleIdentifier: "com.notchkit.tests.provider",
            extensionBundleIdentifier: "com.notchkit.tests.provider.extension",
            extensionPointIdentifier: "com.notchkit.extension-point",
            minimumMacOSVersion: ExtensionVersion(major: 26, minor: 0, patch: 0),
            protocolVersions: ExtensionProtocolVersionRange(minimum: 1, maximum: 3),
            architectures: [.arm64, .x86_64]
        )
        return ExtensionPackageManifest(
            metadata: metadata,
            artifact: ExtensionPackageArtifact(kind: .appExtension, appExtension: appExtension),
            permissions: [
                .camera(owner: .extension, usageDescriptionKey: "CameraUsageDescription"),
                .mediaControl(required: false, owner: .host, usageDescriptionKey: "MediaUsageDescription")
            ],
            hostActions: [.openDestination],
            entryPoints: [
                ExtensionPackageEntryPoint(
                    entryPoint: metadata.entryPoints[0],
                    presentationMode: .remoteScene,
                    sceneName: "main"
                )
            ]
        )
    }
}
