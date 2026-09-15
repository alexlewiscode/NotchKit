//
//  TestHostIsolationTests.swift
//  NotchKitTests
//
//  Proves the app-hosted test bundle runs with production startup disabled and
//  with storage redirected away from the real application support directory.
//

import NotchExtensionSDK
import XCTest
@testable import NotchKit

@MainActor
final class TestHostIsolationTests: XCTestCase {

    func testTestHostIsDetected() {
        XCTAssertTrue(
            TestHostPolicy.isActive,
            "The app-hosted test bundle must be recognized as a test host"
        )
    }

    func testProductionStartupDidNotRun() {
        XCTAssertFalse(
            TestHostPolicy.productionStartupDidRun,
            "Migration, bootstrap, and service startup must not run under a test host"
        )
    }

    func testShelfStorageUsesIsolationRootNotRealApplicationSupport() {
        let storage = ShelfPersistenceService.shared.storageDirectory.standardizedFileURL
        let root = TestHostPolicy.isolationRoot.standardizedFileURL

        XCTAssertTrue(
            storage.path.hasPrefix(root.path),
            "Shelf storage \(storage.path) must live under \(root.path)"
        )

        if let realShelf = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
            .standardizedFileURL
        {
            XCTAssertFalse(
                storage.path.hasPrefix(realShelf.path),
                "Shelf storage must not resolve to the real application support directory"
            )
        }
    }
}
