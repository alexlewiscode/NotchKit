//
//  HUDStatusProviderTests.swift
//  NotchKitTests
//

import XCTest
@testable import NotchKit

@MainActor
final class HUDStatusProviderTests: XCTestCase {

    func testGrantedPresentationConfirmsAccessWithoutRequestAction() {
        let presentation = HUDInputAccessPresentation(hasInputAccess: true)

        XCTAssertEqual(presentation.message, "Accessibility access is granted.")
        XCTAssertEqual(presentation.symbolName, "checkmark.circle.fill")
        XCTAssertFalse(presentation.showsRequestButton)
    }

    func testRequiredPresentationExplainsAccessAndShowsRequestAction() {
        let presentation = HUDInputAccessPresentation(hasInputAccess: false)

        XCTAssertEqual(
            presentation.message,
            "Accessibility access is required to replace the system HUD."
        )
        XCTAssertEqual(presentation.symbolName, "exclamationmark.triangle.fill")
        XCTAssertTrue(presentation.showsRequestButton)
    }

    func testRefreshOnlyReadsStatus() async {
        var reads = 0
        let provider = HUDStatusProvider(readStatus: {
            reads += 1
            return true
        })

        await provider.refresh()
        XCTAssertEqual(reads, 1)
        XCTAssertTrue(provider.hasInputAccess)

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
        XCTAssertFalse(provider.hasInputAccess)
    }
}
