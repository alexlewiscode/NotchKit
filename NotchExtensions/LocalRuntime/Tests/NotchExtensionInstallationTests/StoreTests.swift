import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK
import XCTest

final class StoreTests: XCTestCase {
    func testMissingStoreLoadsEmptyCurrentSnapshot() throws {
        let store = JSONInstalledExtensionStore(rootURL: try temporaryDirectory())
        let snapshot = try store.load()
        XCTAssertEqual(snapshot.schemaVersion, 3)
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

    func testSchemaV2MigratesToLocalProvenanceAndPersistsSchemaV3() throws {
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
            declaredPermissions: [],
            declaredHostActions: [],
            signature: .init(teamIdentifier: "TEAM", providerDesignatedRequirement: "p", extensionDesignatedRequirements: [:]),
            installedAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            desiredEnabled: false,
            localStatus: .installed
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object = try XCTUnwrap(JSONSerialization.jsonObject(
            with: encoder.encode(InstalledExtensionSnapshot(schemaVersion: 2, records: [record]))
        ) as? [String: Any])
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0].removeValue(forKey: "origin")
        records[0].removeValue(forKey: "marketplaceReceipt")
        records[0].removeValue(forKey: "previousRelease")
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: store.fileURL)

        let migrated = try store.load()
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.records[0].origin, .localDeveloper)
        XCTAssertNil(migrated.records[0].marketplaceReceipt)
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        XCTAssertEqual(persisted["schemaVersion"] as? Int, 3)
    }
}
