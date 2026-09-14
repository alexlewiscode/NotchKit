//
//  ClosedNotchSelectionTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import NotchExtensionRuntime
import XCTest

final class ClosedNotchSelectionTests: XCTestCase {
    private let owner = try! ExtensionIdentity("com.boringnotch.test")

    func testHigherPriorityWins() {
        let low = TestFactory.contribution("a", extensionID: owner, priority: 1)
        let high = TestFactory.contribution("b", extensionID: owner, priority: 5)

        let winners = ClosedNotchSelection.select(
            from: [low, high], snapshot: .empty
        )

        XCTAssertEqual(winners[.exclusion]?.id, high.id)
    }

    func testEqualPriorityTieBreaksDeterministically() {
        let alpha = TestFactory.contribution("a", extensionID: owner, priority: 10, tieBreaker: "alpha")
        let beta = TestFactory.contribution("b", extensionID: owner, priority: 10, tieBreaker: "beta")

        let forward = ClosedNotchSelection.select(from: [beta, alpha], snapshot: .empty)
        let reversed = ClosedNotchSelection.select(from: [alpha, beta], snapshot: .empty)

        XCTAssertEqual(forward[.exclusion]?.id, alpha.id)
        XCTAssertEqual(reversed[.exclusion]?.id, alpha.id)
    }

    func testEqualPriorityAndTieBreakerUsesIdentity() {
        let a = TestFactory.contribution("com.boringnotch.contribution.a", extensionID: owner, priority: 1, tieBreaker: "same")
        let b = TestFactory.contribution("com.boringnotch.contribution.b", extensionID: owner, priority: 1, tieBreaker: "same")

        let winners = ClosedNotchSelection.select(from: [b, a], snapshot: .empty)
        XCTAssertEqual(winners[.exclusion]?.id, a.id)
    }

    func testRecencyWinsBeforeTieBreaker() {
        let older = TestFactory.contribution("a", extensionID: owner, priority: 1, tieBreaker: "alpha")
        let newer = TestFactory.contribution("b", extensionID: owner, priority: 1, tieBreaker: "beta")

        let winners = ClosedNotchSelection.select(
            from: [older, newer],
            snapshot: .empty,
            recency: [newer.id: 2, older.id: 1]
        )

        XCTAssertEqual(winners[.exclusion]?.id, newer.id)
    }

    func testUnavailableContributionsAreExcluded() {
        let available = TestFactory.contribution("a", extensionID: owner, priority: 10) { _ in true }
        let unavailable = TestFactory.contribution("b", extensionID: owner, priority: 100) { _ in false }

        let winners = ClosedNotchSelection.select(
            from: [available, unavailable], snapshot: .empty
        )

        XCTAssertEqual(winners[.exclusion]?.id, available.id)
    }

    func testRegionsAreIndependent() {
        let leading = TestFactory.contribution("a", extensionID: owner, region: .leading, priority: 1)
        let trailing = TestFactory.contribution("b", extensionID: owner, region: .trailing, priority: 1)

        let winners = ClosedNotchSelection.select(from: [leading, trailing], snapshot: .empty)

        XCTAssertEqual(winners[.leading]?.id, leading.id)
        XCTAssertEqual(winners[.trailing]?.id, trailing.id)
        XCTAssertNil(winners[.exclusion])
    }

    func testNoAvailableContributionYieldsNoWinner() {
        let unavailable = TestFactory.contribution("a", extensionID: owner) { _ in false }
        let winners = ClosedNotchSelection.select(from: [unavailable], snapshot: .empty)
        XCTAssertTrue(winners.isEmpty)
    }
}