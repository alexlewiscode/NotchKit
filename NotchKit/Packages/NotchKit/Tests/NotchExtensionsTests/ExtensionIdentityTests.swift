//
//  ExtensionIdentityTests.swift
//  NotchExtensionsTests
//

import NotchAPI
import XCTest

final class ExtensionIdentityTests: XCTestCase {
    func testAcceptsReverseDNSIdentity() throws {
        let id = try ExtensionIdentity("com.boringnotch.home")
        XCTAssertEqual(id.rawValue, "com.boringnotch.home")
    }

    func testAcceptsHyphenatedComponents() throws {
        _ = try ExtensionIdentity("com.boring-not.media-controller")
    }

    func testRejectsTooFewComponents() {
        XCTAssertThrowsError(try ExtensionIdentity("home"))
    }

    func testRejectsEmptyComponents() {
        XCTAssertThrowsError(try ExtensionIdentity("com..boringnotch"))
    }

    func testRejectsInvalidCharacters() {
        XCTAssertThrowsError(try ExtensionIdentity("com.boring notch.home"))
    }

    func testRejectsLeadingOrTrailingHyphen() {
        XCTAssertThrowsError(try ExtensionIdentity("com.-boring.notch"))
        XCTAssertThrowsError(try ExtensionIdentity("com.boring-.notch"))
    }

    func testRejectsLeadingOrTrailingDot() {
        XCTAssertThrowsError(try ExtensionIdentity(".com.boring.notch"))
        XCTAssertThrowsError(try ExtensionIdentity("com.boring.notch."))
    }

    func testIdentityOrderingIsStable() throws {
        let a = try ExtensionIdentity("com.boringnotch.home")
        let b = try ExtensionIdentity("com.boringnotch.shelf")
        XCTAssertLessThan(a, b)
    }
}