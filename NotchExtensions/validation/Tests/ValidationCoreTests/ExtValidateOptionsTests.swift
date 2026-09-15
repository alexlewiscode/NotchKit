//
//  ExtValidateOptionsTests.swift
//  ValidationCoreTests
//
//  CLI default/override behaviour and error handling.
//

import XCTest
import NotchExtensionSDK
@testable import ValidationCore

final class ExtValidateOptionsTests: XCTestCase {

    func testSDKDefaultUsesSharedCurrentValue() throws {
        let options = try ExtValidateOptionsParser.parse(["manifest.json"])
        XCTAssertEqual(options.sdkVersion, ExtensionAPIVersion.current)
        XCTAssertEqual(options.sdkVersion, ExtensionAPIVersion(major: 1, minor: 1, patch: 0))
    }

    func testHostDefaultIsUnchanged() throws {
        let options = try ExtValidateOptionsParser.parse(["manifest.json"])
        XCTAssertEqual(options.hostVersion, ExtensionVersion(major: 1, minor: 0, patch: 0))
    }

    func testExplicitVersionsOverrideDefaults() throws {
        let options = try ExtValidateOptionsParser.parse([
            "manifest.json",
            "--host-version", "2.1.0",
            "--sdk-version", "1.3.0",
        ])
        XCTAssertEqual(options.hostVersion, ExtensionVersion(major: 2, minor: 1, patch: 0))
        XCTAssertEqual(options.sdkVersion, ExtensionAPIVersion(major: 1, minor: 3, patch: 0))
        XCTAssertEqual(options.manifestPaths, ["manifest.json"])
    }

    func testMultipleManifestsAreCollected() throws {
        let options = try ExtValidateOptionsParser.parse(["a.json", "b.json"])
        XCTAssertEqual(options.manifestPaths, ["a.json", "b.json"])
    }

    func testInvalidVersionIsRejected() {
        XCTAssertThrowsError(
            try ExtValidateOptionsParser.parse(["m.json", "--sdk-version", "1.2"])
        ) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .invalidVersion(option: "--sdk-version"))
        }
    }

    func testMissingValueIsRejected() {
        XCTAssertThrowsError(
            try ExtValidateOptionsParser.parse(["m.json", "--host-version"])
        ) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .missingValue(option: "--host-version"))
        }
    }

    func testUnknownOptionIsRejected() {
        XCTAssertThrowsError(
            try ExtValidateOptionsParser.parse(["m.json", "--nope"])
        ) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .unknownOption("--nope"))
        }
    }

    func testNoManifestsIsRejected() {
        XCTAssertThrowsError(try ExtValidateOptionsParser.parse([])) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .noManifests)
        }
    }

    func testHelpIsSignalled() {
        XCTAssertThrowsError(try ExtValidateOptionsParser.parse(["--help"])) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .helpRequested)
        }
        XCTAssertThrowsError(try ExtValidateOptionsParser.parse(["-h"])) { error in
            XCTAssertEqual(error as? ExtValidateOptionsError, .helpRequested)
        }
    }
}
