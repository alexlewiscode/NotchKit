//
//  ManifestValidatorTests.swift
//  ValidationCoreTests
//
//  Fixture-driven tests for the structural and host-compatibility phases.
//

import XCTest
import NotchExtensionSDK
@testable import ValidationCore

final class ManifestValidatorTests: XCTestCase {

    private static let hostVersion = ExtensionVersion(major: 1, minor: 0, patch: 0)
    private static let sdkVersion = ExtensionAPIVersion(major: 1, minor: 0, patch: 0)

    /// `.../validation/Fixtures`, resolved from this source file so the tests do
    /// not depend on the process working directory.
    private static let fixturesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ValidationCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // validation
        .appendingPathComponent("Fixtures")

    private func loadFixture(_ relativePath: String) throws -> Data {
        let url = Self.fixturesRoot.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    private func validateFixture(_ relativePath: String) throws -> [ValidationIssue] {
        ManifestValidator.validate(
            data: try loadFixture(relativePath),
            hostVersion: Self.hostVersion,
            sdkVersion: Self.sdkVersion
        )
    }

    // MARK: Valid fixtures

    func testValidFixturesProduceNoIssues() throws {
        for fixture in ["valid/hello-extension.json", "valid/battery.json"] {
            let issues = try validateFixture(fixture)
            XCTAssertTrue(issues.isEmpty, "\(fixture) should be valid but produced \(issues)")
        }
    }

    // MARK: Invalid fixtures

    private struct Expectation {
        let fixture: String
        let phase: ValidationPhase
        let code: String
        let severity: ValidationSeverity
    }

    private let invalidFixtures: [Expectation] = [
        // Structural
        .init(fixture: "invalid/unknown-top-level-key.json",
              phase: .structural, code: ValidationCode.unknownKey, severity: .error),
        .init(fixture: "invalid/unknown-entry-point-key.json",
              phase: .structural, code: ValidationCode.unknownEntryPointKey, severity: .error),
        .init(fixture: "invalid/bad-identity.json",
              phase: .structural, code: ValidationCode.invalidIdentity, severity: .error),
        .init(fixture: "invalid/bad-version-range.json",
              phase: .structural, code: ValidationCode.invalidVersionRange, severity: .error),
        .init(fixture: "invalid/invalid-version.json",
              phase: .structural, code: ValidationCode.invalidVersion, severity: .error),
        .init(fixture: "invalid/duplicate-entry-point-id.json",
              phase: .structural, code: ValidationCode.duplicateEntryPointID, severity: .error),
        .init(fixture: "invalid/invalid-capability.json",
              phase: .structural, code: ValidationCode.invalidCapability, severity: .error),
        .init(fixture: "invalid/duplicate-capability.json",
              phase: .structural, code: ValidationCode.duplicateCapability, severity: .error),
        .init(fixture: "invalid/invalid-artifact-kind.json",
              phase: .structural, code: ValidationCode.invalidArtifactKind, severity: .error),
        .init(fixture: "invalid/invalid-entry-point-kind.json",
              phase: .structural, code: ValidationCode.invalidEntryPointKind, severity: .error),
        .init(fixture: "invalid/scene-name-for-compiled-in.json",
              phase: .structural, code: ValidationCode.sceneNameNotAllowed, severity: .error),
        .init(fixture: "invalid/invalid-entry-point-metadata.json",
              phase: .structural, code: ValidationCode.invalidEntryPointMetadata, severity: .error),
        .init(fixture: "invalid/missing-required-field.json",
              phase: .structural, code: ValidationCode.missingRequiredField, severity: .error),
        .init(fixture: "invalid/not-a-json-object.json",
              phase: .structural, code: ValidationCode.invalidJSON, severity: .error),
        // Host compatibility
        .init(fixture: "invalid/unsupported-artifact-kind.json",
              phase: .hostCompatibility, code: ValidationCode.unsupportedArtifactKind, severity: .error),
        .init(fixture: "invalid/unsupported-host-version.json",
              phase: .hostCompatibility, code: ValidationCode.unsupportedHostVersion, severity: .error),
        .init(fixture: "invalid/unsupported-sdk-version.json",
              phase: .hostCompatibility, code: ValidationCode.unsupportedSDKVersion, severity: .error),
        .init(fixture: "invalid/undeclared-capability.json",
              phase: .hostCompatibility, code: ValidationCode.undeclaredCapability, severity: .error),
        .init(fixture: "invalid/capability-without-entrypoint.json",
              phase: .hostCompatibility, code: ValidationCode.capabilityWithoutEntryPoint, severity: .error),
    ]

    func testInvalidFixturesProduceExpectedSingleIssue() throws {
        for expectation in invalidFixtures {
            let issues = try validateFixture(expectation.fixture)
            XCTAssertEqual(
                issues.count, 1,
                "\(expectation.fixture) should produce exactly one issue but produced \(issues)"
            )
            guard let issue = issues.first else { continue }
            XCTAssertEqual(issue.phase, expectation.phase, "phase for \(expectation.fixture)")
            XCTAssertEqual(issue.code, expectation.code, "code for \(expectation.fixture)")
            XCTAssertEqual(issue.severity, expectation.severity, "severity for \(expectation.fixture)")
        }
    }

    func testStructuralFailureShortCircuitsCompatibility() throws {
        // A manifest with both a structural defect (bad identity) and a host
        // mismatch (host range starts at 2.0.0) must report only the structural
        // issue: compatibility is not evaluated when structure is unsound.
        let json = """
        {
          "id": "bad",
          "displayName": "Both",
          "iconSystemName": "xmark",
          "extensionVersion": "1.0.0",
          "apiVersion": "1.0.0",
          "supportedHostVersions": ">=2.0.0",
          "supportedSDKVersions": ">=1.0.0 <2.0.0",
          "capabilities": ["open-destination"],
          "artifactKind": "compiled-in",
          "entryPoints": [
            { "id": "com.notchkit.both.page", "kind": "open-destination" }
          ],
          "defaultEnabled": false,
          "source": "firstParty"
        }
        """
        let issues = ManifestValidator.validate(
            data: Data(json.utf8),
            hostVersion: Self.hostVersion,
            sdkVersion: Self.sdkVersion
        )
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.phase, .structural)
        XCTAssertEqual(issues.first?.code, ValidationCode.invalidIdentity)
        XCTAssertFalse(issues.contains { $0.phase == .hostCompatibility })
    }

    func testMissingRequiredFieldReportsJsonPath() throws {
        let issues = try validateFixture("invalid/missing-required-field.json")
        XCTAssertEqual(issues.first?.path, "$.displayName")
    }

    func testUnknownKeyReportsJsonPath() throws {
        let issues = try validateFixture("invalid/unknown-top-level-key.json")
        XCTAssertEqual(issues.first?.path, "$.bogusTopLevel")
    }
}
