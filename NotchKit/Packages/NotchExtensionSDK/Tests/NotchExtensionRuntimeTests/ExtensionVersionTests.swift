//
//  ExtensionVersionTests.swift
//  NotchExtensionRuntimeTests
//
//  Tests for semantic versions and version ranges.
//

import XCTest
import NotchExtensionSDK

final class ExtensionVersionTests: XCTestCase {
    func testParsesStrictSemver() {
        XCTAssertEqual(ExtensionVersion("1.2.3"), ExtensionVersion(major: 1, minor: 2, patch: 3))
        XCTAssertNil(ExtensionVersion("1.2"))
        XCTAssertNil(ExtensionVersion("1.2.3.4"))
        XCTAssertNil(ExtensionVersion("v1.2.3"))
        XCTAssertNil(ExtensionVersion("1.2.x"))
    }

    func testOrderingIsComponentWise() {
        XCTAssertLessThan(ExtensionVersion(major: 1, minor: 0, patch: 0), ExtensionVersion(major: 1, minor: 0, patch: 1))
        XCTAssertLessThan(ExtensionVersion(major: 1, minor: 9, patch: 9), ExtensionVersion(major: 2, minor: 0, patch: 0))
    }

    func testVersionRangeContains() {
        let range = ExtensionVersionRange(
            minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
            maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
        )
        XCTAssertFalse(range.contains(ExtensionVersion(major: 0, minor: 9, patch: 0)))
        XCTAssertTrue(range.contains(ExtensionVersion(major: 1, minor: 0, patch: 0)))
        XCTAssertTrue(range.contains(ExtensionVersion(major: 1, minor: 5, patch: 0)))
        XCTAssertFalse(range.contains(ExtensionVersion(major: 2, minor: 0, patch: 0)))
    }

    func testUnboundedRange() {
        let range = ExtensionVersionRange(minimum: ExtensionVersion(major: 1, minor: 0, patch: 0))
        XCTAssertTrue(range.contains(ExtensionVersion(major: 99, minor: 0, patch: 0)))
    }

    func testParsesRangeStrings() {
        XCTAssertEqual(
            ExtensionVersionRange.parse(">=1.0.0 <2.0.0"),
            ExtensionVersionRange(
                minimum: ExtensionVersion(major: 1, minor: 0, patch: 0),
                maximum: ExtensionVersion(major: 2, minor: 0, patch: 0)
            )
        )
        XCTAssertEqual(
            ExtensionVersionRange.parse(">=1.0.0"),
            ExtensionVersionRange(minimum: ExtensionVersion(major: 1, minor: 0, patch: 0))
        )
        XCTAssertNil(ExtensionVersionRange.parse(">=2.0.0 <1.0.0"))
        XCTAssertNil(ExtensionVersionRange.parse("not-a-version"))
    }

    func testVersionCodableRoundTrip() throws {
        let version = ExtensionVersion(major: 1, minor: 2, patch: 3)
        let data = try JSONEncoder().encode(version)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"1.2.3\"")
        XCTAssertEqual(try JSONDecoder().decode(ExtensionVersion.self, from: data), version)
    }

    func testRangeCodableRoundTrip() throws {
        let range = ExtensionVersionRange.parse(">=1.0.0 <2.0.0")!
        let data = try JSONEncoder().encode(range)
        XCTAssertEqual(try JSONDecoder().decode(ExtensionVersionRange.self, from: data), range)
    }
}
