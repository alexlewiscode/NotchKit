//
//  ExtensionIdentityTests.swift
//  NotchExtensionRuntimeTests
//

import NotchExtensionSDK
import XCTest

final class ExtensionIdentityTests: XCTestCase {
    func testAcceptsReverseDNSIdentity() throws {
        let id = try ExtensionIdentity("com.notchkit.home")
        XCTAssertEqual(id.rawValue, "com.notchkit.home")
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
        let a = try ExtensionIdentity("com.notchkit.home")
        let b = try ExtensionIdentity("com.notchkit.shelf")
        XCTAssertLessThan(a, b)
    }
}