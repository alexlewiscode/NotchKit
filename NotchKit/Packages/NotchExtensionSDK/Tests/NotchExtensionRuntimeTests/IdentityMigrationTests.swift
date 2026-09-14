//
//  IdentityMigrationTests.swift
//  NotchExtensionRuntimeTests
//
//  Unit coverage for the pure identity-migration transforms, including
//  idempotency and partial-failure handling.
//

import Foundation
import XCTest
import NotchExtensionSDK
import NotchExtensionRuntime

final class IdentityMigrationTests: XCTestCase {

    // MARK: - Identifier rewrite

    func testMigratesLegacyExtensionIdentities() {
        XCTAssertEqual(IdentityMigration.migrateIdentifier("com.boringnotch.home"), "com.notchkit.home")
        XCTAssertEqual(IdentityMigration.migrateIdentifier("com.boringnotch.shelf"), "com.notchkit.shelf")
        XCTAssertEqual(
            IdentityMigration.migrateIdentifier("com.boringnotch.destination.home"),
            "com.notchkit.destination.home"
        )
    }

    func testLeavesForeignAndCurrentIdentifiersUntouched() {
        XCTAssertEqual(IdentityMigration.migrateIdentifier("com.notchkit.home"), "com.notchkit.home")
        XCTAssertEqual(IdentityMigration.migrateIdentifier("com.example.other"), "com.example.other")
        XCTAssertEqual(IdentityMigration.migrateIdentifier(""), "")
    }

    func testIdentifierMigrationIsIdempotent() {
        let once = IdentityMigration.migrateIdentifier("com.boringnotch.home")
        let twice = IdentityMigration.migrateIdentifier(once)
        XCTAssertEqual(once, twice)
    }

    // MARK: - Extension state

    private func encodedState(_ enabled: [String: Bool]) -> Data {
        try! JSONEncoder().encode(ExtensionStateSnapshot(enabled: enabled))
    }

    func testMigratesExtensionStateKeys() {
        let legacy = encodedState([
            "com.boringnotch.home": true,
            "com.boringnotch.shelf": false,
        ])
        guard let migratedData = IdentityMigration.migrateExtensionStateData(legacy),
              let migrated = try? JSONDecoder().decode(ExtensionStateSnapshot.self, from: migratedData) else {
            return XCTFail("expected migratable state")
        }
        XCTAssertEqual(migrated.enabled, ["com.notchkit.home": true, "com.notchkit.shelf": false])
        XCTAssertEqual(migrated.schemaVersion, ExtensionStateSnapshot.currentSchemaVersion)
    }

    func testMigratedStateIsIdempotent() {
        let legacy = encodedState(["com.boringnotch.home": true])
        let first = IdentityMigration.migrateExtensionStateData(legacy)!
        let second = IdentityMigration.migrateExtensionStateData(first)!
        let firstSnapshot = try! JSONDecoder().decode(ExtensionStateSnapshot.self, from: first)
        let secondSnapshot = try! JSONDecoder().decode(ExtensionStateSnapshot.self, from: second)
        XCTAssertEqual(firstSnapshot, secondSnapshot)
        XCTAssertEqual(secondSnapshot.enabled, ["com.notchkit.home": true])
    }

    func testCorruptStateReturnsNilForRetry() {
        XCTAssertNil(IdentityMigration.migrateExtensionStateData(Data("not json".utf8)))
        XCTAssertNil(IdentityMigration.migrateExtensionStateData(Data()))
    }

    func testEmptyStateMigratesToEmptyState() {
        let migrated = IdentityMigration.migrateExtensionStateData(encodedState([:]))!
        let snapshot = try! JSONDecoder().decode(ExtensionStateSnapshot.self, from: migrated)
        XCTAssertTrue(snapshot.enabled.isEmpty)
    }

    // MARK: - Defaults merge

    func testCopiesOnlyMissingDefaults() {
        let legacy: [String: Any] = ["menubarIcon": true, "notchHeight": 220]
        let existing: Set<String> = ["menubarIcon"]
        let missing = IdentityMigration.missingDefaults(legacy: legacy) { existing.contains($0) }
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing["notchHeight"] as? Int, 220)
        XCTAssertNil(missing["menubarIcon"])
    }

    func testDefaultsMergeIsIdempotentAcrossRuns() {
        let legacy: [String: Any] = ["a": 1, "b": 2]
        let first = IdentityMigration.missingDefaults(legacy: legacy) { _ in false }
        XCTAssertEqual(Set(first.keys), ["a", "b"])
        let present = Set(first.keys)
        let second = IdentityMigration.missingDefaults(legacy: legacy) { present.contains($0) }
        XCTAssertTrue(second.isEmpty)
    }

    func testPartialFailureLeavesRemainingKeysAvailableForRetry() {
        let legacy: [String: Any] = ["a": 1, "b": 2, "c": 3]
        // Simulate a run that only persisted "a" before failing.
        let present: Set<String> = ["a"]
        let missing = IdentityMigration.missingDefaults(legacy: legacy) { present.contains($0) }
        XCTAssertEqual(Set(missing.keys), ["b", "c"])
    }

    // MARK: - Completion summary

    func testSummaryValidityReflectsPartialApplication() {
        let complete = IdentityMigration.Summary(
            defaultsMigrated: 3, extensionStateMigrated: true,
            shelfItemsCopied: true, invalidBookmarkCount: 0
        )
        XCTAssertTrue(complete.isValidCompletion)

        let partial = IdentityMigration.Summary(
            defaultsMigrated: 3, extensionStateMigrated: false,
            shelfItemsCopied: true, invalidBookmarkCount: 0
        )
        XCTAssertFalse(partial.isValidCompletion)
    }

    func testSummaryRoundTripsWithoutUserData() {
        let summary = IdentityMigration.Summary(
            defaultsMigrated: 2, extensionStateMigrated: true,
            shelfItemsCopied: true, invalidBookmarkCount: 1
        )
        let data = try! JSONEncoder().encode(summary)
        let decoded = try! JSONDecoder().decode(IdentityMigration.Summary.self, from: data)
        XCTAssertEqual(decoded, summary)
    }
}