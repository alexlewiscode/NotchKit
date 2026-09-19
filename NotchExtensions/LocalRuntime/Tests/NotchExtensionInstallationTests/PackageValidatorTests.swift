import Foundation
import NotchExtensionInstallation
import XCTest

final class PackageValidatorTests: XCTestCase {
    func testValidatesPackageAndExactEmbeddedManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeExtractedPackage(at: root)
        let package = try DefaultExtractedPackageValidator().validate(packageRootURL: root)
        XCTAssertEqual(package.manifest.id.rawValue, "com.example.feature.timer")
        XCTAssertEqual(package.providerBundleIdentifier, "com.example.provider")
        XCTAssertEqual(package.extensionBundleIdentifiers, ["com.example.provider.TimerExtension"])
        XCTAssertNotEqual(package.manifest.id.rawValue, package.extensionBundleIdentifiers[0])
    }

    func testRejectsMissingAndMalformedManifest() throws {
        let root = try temporaryDirectory()
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .missingManifest)
        }
        try Data("{}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .invalidManifest)
        }
    }

    func testRejectsByteDifferentEmbeddedManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeExtractedPackage(at: root, embeddedData: Data("different".utf8))
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .embeddedManifestMismatch)
        }
    }

    func testRejectsProviderIdentityMismatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeExtractedPackage(at: root)
        try writePlist([
            "CFBundleIdentifier": "com.attacker.provider",
            "CFBundleShortVersionString": "1.2.3",
        ], to: root.appendingPathComponent("payload/Provider.app/Contents/Info.plist"))
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .invalidProviderIdentity)
        }
    }

    func testRejectsExtensionVersionMismatch() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeExtractedPackage(at: root)
        try writePlist([
            "CFBundleIdentifier": "com.example.provider.TimerExtension",
            "CFBundleShortVersionString": "9.0.0",
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": "com.example.extension-point"],
        ], to: root.appendingPathComponent("payload/Provider.app/Contents/Extensions/TimerExtension.appex/Contents/Info.plist"))
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .invalidExtensionVersion("com.example.provider.TimerExtension"))
        }
    }

    func testRejectsMissingOrMismatchedExtensionPoint() throws {
        for point in [nil, "wrong.point"] as [String?] {
            let root = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            _ = try makeExtractedPackage(at: root)
            var plist: [String: Any] = [
                "CFBundleIdentifier": "com.example.provider.TimerExtension",
                "CFBundleShortVersionString": "1.2.3",
            ]
            if let point { plist["EXAppExtensionAttributes"] = ["EXExtensionPointIdentifier": point] }
            try writePlist(plist, to: root.appendingPathComponent("payload/Provider.app/Contents/Extensions/TimerExtension.appex/Contents/Info.plist"))
            XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
                XCTAssertEqual($0 as? ExtractedPackageError, .invalidExtensionPoint("com.example.provider.TimerExtension"))
            }
        }
    }

    func testRejectsUnexpectedNestedAppExtension() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeExtractedPackage(at: root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("payload/Provider.app/Contents/PlugIns/Other.appex"),
            withIntermediateDirectories: true
        )
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            guard case .unexpectedAppExtension = $0 as? ExtractedPackageError else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
    }

    func testStrictManifestRejectsUnknownKeysAndWrongTypes() throws {
        let manifest = try JSONEncoder().encode(packageManifest())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: manifest) as? [String: Any])
        object["unexpected"] = true
        XCTAssertThrowsError(try StrictExtensionPackageManifestValidator().decodeAndValidate(data: try JSONSerialization.data(withJSONObject: object)))
        object.removeValue(forKey: "unexpected")
        object["schemaVersion"] = "2"
        XCTAssertThrowsError(try StrictExtensionPackageManifestValidator().decodeAndValidate(data: try JSONSerialization.data(withJSONObject: object)))
    }

    func testRejectsMetadataIdentityEqualToExtensionBundleIdentifier() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try JSONEncoder().encode(packageManifest(id: "com.example.provider.TimerExtension"))
        let provider = root.appendingPathComponent("payload/Provider.app/Contents", isDirectory: true)
        let extensionURL = provider.appendingPathComponent("Extensions/TimerExtension.appex/Contents", isDirectory: true)
        let resources = provider.appendingPathComponent("Resources/NotchKitExtension", isDirectory: true)
        try FileManager.default.createDirectory(at: extensionURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try manifest.write(to: root.appendingPathComponent("manifest.json"))
        try manifest.write(to: resources.appendingPathComponent("manifest.json"))
        try writePlist(["CFBundleIdentifier": "com.example.provider", "CFBundleShortVersionString": "1.2.3"], to: provider.appendingPathComponent("Info.plist"))
        try writePlist([
            "CFBundleIdentifier": "com.example.provider.TimerExtension",
            "CFBundleShortVersionString": "1.2.3",
            "EXAppExtensionAttributes": ["EXExtensionPointIdentifier": "com.example.extension-point"],
        ], to: extensionURL.appendingPathComponent("Info.plist"))
        XCTAssertThrowsError(try DefaultExtractedPackageValidator().validate(packageRootURL: root)) {
            XCTAssertEqual($0 as? ExtractedPackageError, .metadataIdentityMatchesExtensionBundle)
        }
    }
}
