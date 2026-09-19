import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
import XCTest

final class StoreTests: XCTestCase {
    func testMissingStoreLoadsEmptyCurrentSnapshot() throws {
        let store = JSONInstalledExtensionStore(rootURL: try temporaryDirectory())
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.schemaVersion, 2)
        XCTAssertTrue(snapshot.records.isEmpty)
    }

    func testRoundTrip() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONInstalledExtensionStore(rootURL: root)
        let record = InstalledExtensionRecord(
            id: try ExtensionIdentity("com.example.provider.extension"),
            extensionVersion: ExtensionVersion("1.2.3")!,
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifiers: ["com.example.provider.extension"],
            relativeInstallPath: "Extensions/com.example.provider.extension",
            manifestSHA256: String(repeating: "a", count: 64),
            declaredPermissions: [.camera(usageDescriptionKey: "NSCameraUsageDescription")],
            declaredHostActions: [.openDestination],
            signature: InstalledCodeSignature(
                teamIdentifier: "TEAM",
                providerDesignatedRequirement: "provider",
                extensionDesignatedRequirements: ["com.example.provider.extension": "extension"]
            ),
            installedAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001),
            desiredEnabled: true,
            localStatus: .installed
        )
        try store.save(InstalledExtensionSnapshot(records: [record]))
        XCTAssertEqual(try store.load().records, [record])
    }

    func testCorruptDataIsPreserved() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONInstalledExtensionStore(rootURL: root)
        let bytes = Data("not json".utf8)
        try bytes.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? InstalledExtensionStoreError, .corruptData)
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }

    func testUnsupportedSchemaIsPreserved() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = JSONInstalledExtensionStore(rootURL: root)
        let bytes = Data(#"{"schemaVersion":99,"records":[]}"#.utf8)
        try bytes.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? InstalledExtensionStoreError, .unsupportedSchemaVersion(99))
        }
        XCTAssertEqual(try Data(contentsOf: store.fileURL), bytes)
    }
}
