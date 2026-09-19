import CryptoKit
import Foundation
import XCTest
@testable import NativeExtensionShared

final class PackageValidatorTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testValidExtractedPackagePasses() throws {
        try writePackage()

        let package = try NativeExtensionPackageValidator.validatePackage(
            at: temporaryDirectory,
            verifyCodeSignature: false
        )

        XCTAssertEqual(package.manifest.id, "com.notchkit.prototype.pomodoro")
        XCTAssertEqual(package.providerApplicationURL.lastPathComponent, "provider.app")
        XCTAssertEqual(package.extensionBundleURL.lastPathComponent, "extension.appex")
    }

    func testManifestCannotClaimDifferentProvider() throws {
        try writePackage(providerBundleID: "com.example.different.provider")

        XCTAssertThrowsError(
            try NativeExtensionPackageValidator.validatePackage(
                at: temporaryDirectory,
                verifyCodeSignature: false
            )
        ) { error in
            XCTAssertEqual(
                error as? NativeExtensionPackageError,
                .invalidProviderBundleIdentifier(
                    expected: "com.notchkit.prototype.pomodoro.provider",
                    actual: "com.example.different.provider"
                )
            )
        }
    }

    func testTamperedManifestIsRejected() throws {
        try writePackage()
        let manifestURL = temporaryDirectory.appending(path: "manifest.json")
        var data = try Data(contentsOf: manifestURL)
        data.append(0x20)
        try data.write(to: manifestURL)

        XCTAssertThrowsError(
            try NativeExtensionPackageValidator.validatePackage(
                at: temporaryDirectory,
                verifyCodeSignature: false
            )
        ) { error in
            XCTAssertEqual(error as? NativeExtensionPackageError, .manifestHashMismatch)
        }
    }

    private func writePackage(
        providerBundleID: String = "com.notchkit.prototype.pomodoro.provider"
    ) throws {
        let manifest = makeManifest()
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: temporaryDirectory.appending(path: "manifest.json"))
        let signature = [
            "manifestSHA256": sha256(manifestData),
            "providerBundleIdentifier": manifest.providerBundleIdentifier,
            "extensionBundleIdentifier": manifest.extensionBundleIdentifier,
            "verification": "apple-code-signature",
        ]
        try JSONSerialization.data(withJSONObject: signature)
            .write(to: temporaryDirectory.appending(path: "signature.json"))

        let providerURL = temporaryDirectory.appending(path: "payload/provider.app")
        let extensionURL = providerURL.appending(path: "Contents/Extensions/extension.appex")
        try FileManager.default.createDirectory(
            at: extensionURL.appending(path: "Contents"),
            withIntermediateDirectories: true
        )
        try writeInfoPlist(bundleID: providerBundleID, to: providerURL)
        try writeInfoPlist(
            bundleID: "com.notchkit.prototype.pomodoro.provider.extension",
            to: extensionURL
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeInfoPlist(bundleID: String, to bundleURL: URL) throws {
        let contentsURL = bundleURL.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID],
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appending(path: "Info.plist"))
    }
}
