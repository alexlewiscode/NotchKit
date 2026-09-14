//
//  ExtensionMetadataTests.swift
//  NotchExtensionRuntimeTests
//
//  The canonical manifest decodes into metadata and round-trips.
//

import XCTest
import NotchExtensionSDK

final class ExtensionMetadataTests: XCTestCase {
    /// Mirrors NotchExtensions/examples/HelloExtension/manifest.json.
    static let helloManifestJSON = """
    {
      "id": "com.notchkit.example.hello",
      "displayName": "Hello Extension",
      "summary": "Reference example.",
      "iconSystemName": "hand.wave",
      "extensionVersion": "1.0.0",
      "apiVersion": "1.0.0",
      "supportedHostVersions": ">=1.0.0",
      "supportedSDKVersions": ">=1.0.0 <2.0.0",
      "capabilities": ["open-destination"],
      "artifactKind": "compiled-in",
      "entryPoints": [
        { "id": "com.notchkit.example.hello.page", "kind": "open-destination" }
      ],
      "defaultEnabled": false,
      "source": "firstParty"
    }
    """

    func testDecodesCanonicalManifest() throws {
        let metadata = try JSONDecoder().decode(
            ExtensionMetadata.self,
            from: Data(Self.helloManifestJSON.utf8)
        )
        XCTAssertEqual(metadata.id.rawValue, "com.notchkit.example.hello")
        XCTAssertEqual(metadata.displayName, "Hello Extension")
        XCTAssertEqual(metadata.extensionVersion, ExtensionVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(metadata.artifactKind, .compiledIn)
        XCTAssertEqual(metadata.capabilities, [.openDestination])
        XCTAssertEqual(metadata.entryPoints.count, 1)
        XCTAssertEqual(metadata.entryPoints.first?.kind, .openDestination)
        XCTAssertFalse(metadata.defaultEnabled)
    }

    func testDecodesWithoutOptionalSummaryAndMetadata() throws {
        let json = """
        {
          "id": "com.notchkit.minimal",
          "displayName": "Minimal",
          "iconSystemName": "circle",
          "extensionVersion": "0.1.0",
          "apiVersion": "1.0.0",
          "supportedHostVersions": ">=1.0.0",
          "supportedSDKVersions": ">=1.0.0 <2.0.0",
          "capabilities": [],
          "artifactKind": "compiled-in",
          "entryPoints": [],
          "defaultEnabled": false,
          "source": "firstParty"
        }
        """
        let metadata = try JSONDecoder().decode(ExtensionMetadata.self, from: Data(json.utf8))
        XCTAssertNil(metadata.summary)
        XCTAssertTrue(metadata.entryPoints.isEmpty)
        XCTAssertTrue(metadata.capabilities.isEmpty)
    }

    func testRoundTripsThroughCodable() throws {
        let original = try JSONDecoder().decode(
            ExtensionMetadata.self, from: Data(Self.helloManifestJSON.utf8)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ExtensionMetadata.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testRejectsMalformedIdentity() {
        let json = """
        {
          "id": "not-reverse-dns",
          "displayName": "Bad",
          "iconSystemName": "circle",
          "extensionVersion": "1.0.0",
          "apiVersion": "1.0.0",
          "supportedHostVersions": ">=1.0.0",
          "supportedSDKVersions": ">=1.0.0",
          "capabilities": [],
          "artifactKind": "compiled-in",
          "entryPoints": [],
          "defaultEnabled": false,
          "source": "firstParty"
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(ExtensionMetadata.self, from: Data(json.utf8))
        )
    }

    func testEntryPointsOfKind() throws {
        let metadata = try JSONDecoder().decode(
            ExtensionMetadata.self, from: Data(Self.helloManifestJSON.utf8)
        )
        XCTAssertEqual(metadata.entryPoints(of: .openDestination).count, 1)
        XCTAssertTrue(metadata.entryPoints(of: .settingsDestination).isEmpty)
    }
}
