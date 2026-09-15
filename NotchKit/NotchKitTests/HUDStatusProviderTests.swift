//
//  HUDStatusProviderTests.swift
//  NotchKitTests
//

import XCTest
@testable import NotchKit

@MainActor
final class HUDStatusProviderTests: XCTestCase {

    func testRefreshOnlyReadsStatus() async {
        var reads = 0
        let provider = HUDStatusProvider(readStatus: {
            reads += 1
            return true
        })

        await provider.refresh()
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(provider.isAccessibilityAuthorized)

        await provider.refresh()
        XCTAssertEqual(reads, 2)
    }

    func testRefreshReportsDeniedWithoutRequesting() async {
        var reads = 0
        let provider = HUDStatusProvider(readStatus: {
            reads += 1
            return false
        })

        await provider.refresh()

        XCTAssertEqual(reads, 1)
        XCTAssertFalse(provider.isAccessibilityAuthorized)
    }

    func testApplyDoesNotReadOrStartAnything() {
        var reads = 0
        let provider = HUDStatusProvider(readStatus: {
            reads += 1
            return true
        })

        provider.apply(false)

        XCTAssertEqual(reads, 0)
        XCTAssertFalse(provider.isAccessibilityAuthorized)
    }
}
