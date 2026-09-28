import CryptoKit
import NotchExtensionSDK
import XCTest
@testable import NotchKit

final class MarketplaceTests: XCTestCase {
    private actor RecordingCatalogFetcher: MarketplaceCatalogFetching {
        private(set) var requestCount = 0

        @available(macOS 26.0, *)
        func fetchCatalog(at url: URL, etag: String?) async throws -> MarketplaceCatalogResponse {
            requestCount += 1
            throw MarketplaceCatalogError.invalidResponse
        }
    }

    func testVerifierAcceptsSignedCatalogAndRejectsTampering() throws {
        let fixture = try makeSignedCatalog()

        let snapshot = try MarketplaceCatalogVerifier.verify(
            fixture.data,
            configuration: fixture.configuration,
            now: fixture.now
        )

        XCTAssertEqual(snapshot.revision, "revision-1")
        XCTAssertEqual(snapshot.entries.map(\.displayName), ["Example"])

        var envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: fixture.data) as? [String: Any]
        )
        envelope["signature"] = Data(repeating: 0, count: 64).base64EncodedString()
        let tampered = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        XCTAssertThrowsError(
            try MarketplaceCatalogVerifier.verify(
                tampered,
                configuration: fixture.configuration,
                now: fixture.now
            )
        ) { error in
            XCTAssertEqual(error as? MarketplaceCatalogError, .invalidSignature)
        }
    }

    @MainActor
    func testCoordinatorLoadsOnlyVerifiedUnexpiredOfflineCache() throws {
        let fixture = try makeSignedCatalog()
        let root = TestHostPolicy.isolationRoot
            .appendingPathComponent("marketplace-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskMarketplaceCatalogCache(fileURL: root.appendingPathComponent("catalog.json"))
        try cache.store(MarketplaceCachedCatalog(
            data: fixture.data,
            etag: "\"catalog-1\"",
            verifiedAt: fixture.now
        ))

        let coordinator = MarketplaceCatalogCoordinator(
            configuration: fixture.configuration,
            cache: cache
        )

        XCTAssertEqual(coordinator.phase, .loaded)
        XCTAssertEqual(coordinator.snapshot?.revision, "revision-1")
        XCTAssertTrue(coordinator.isUsingCachedCatalog)
        XCTAssertEqual(coordinator.lastUpdatedAt, fixture.now)
    }

    @MainActor
    func testCoordinatorWithoutHubConfigurationNeverFetches() async {
        let fetcher = RecordingCatalogFetcher()
        let coordinator = MarketplaceCatalogCoordinator(
            configuration: nil,
            fetcher: fetcher
        )

        XCTAssertEqual(coordinator.phase, .unavailable)
        XCTAssertNil(coordinator.snapshot)
        coordinator.refresh()
        XCTAssertEqual(coordinator.phase, .unavailable)
        let requestCount = await fetcher.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testReleaseTrustAndCompatibilityAreIndependent() throws {
        let fixture = try makeSignedCatalog()
        let snapshot = try MarketplaceCatalogVerifier.verify(
            fixture.data,
            configuration: fixture.configuration,
            now: fixture.now
        )
        let entry = try XCTUnwrap(snapshot.entries.first)
        let environment = MarketplaceHostEnvironment(
            macOSVersion: ExtensionVersion(major: 26, minor: 0, patch: 0),
            hostVersion: ExtensionVersion(major: 2, minor: 7, patch: 3),
            sdkVersion: ExtensionVersion(major: 1, minor: 2, patch: 0),
            protocolVersion: 1,
            architecture: .arm64
        )

        XCTAssertEqual(MarketplaceReleaseEvaluator.trust(of: entry), .trusted)
        XCTAssertEqual(
            MarketplaceReleaseEvaluator.compatibility(of: entry.latest, with: environment),
            .compatible
        )

        let oldHost = MarketplaceHostEnvironment(
            macOSVersion: environment.macOSVersion,
            hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0),
            sdkVersion: environment.sdkVersion,
            protocolVersion: environment.protocolVersion,
            architecture: environment.architecture
        )
        guard case .incompatible = MarketplaceReleaseEvaluator.compatibility(
            of: entry.latest,
            with: oldHost
        ) else { return XCTFail("Expected an incompatible host version") }
    }

    func testArtifactVerificationStreamsAndChecksSizeAndDigest() throws {
        let root = TestHostPolicy.isolationRoot
            .appendingPathComponent("marketplace-download-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("artifact.notchkitextension")
        let data = Data(repeating: 0x5a, count: 150_000)
        try data.write(to: url)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        XCTAssertNoThrow(try MarketplaceArtifactDownloader.verify(
            fileAt: url,
            expectedSize: Int64(data.count),
            expectedSHA256: digest
        ))
        XCTAssertThrowsError(try MarketplaceArtifactDownloader.verify(
            fileAt: url,
            expectedSize: Int64(data.count - 1),
            expectedSHA256: digest
        ))
        XCTAssertThrowsError(try MarketplaceArtifactDownloader.verify(
            fileAt: url,
            expectedSize: Int64(data.count),
            expectedSHA256: String(repeating: "0", count: 64)
        )) { error in
            XCTAssertEqual(error as? MarketplaceDownloadError, .digestMismatch)
        }
    }

    func testInstalledExtensionRouteRemainsTyped() throws {
        let id = try ExtensionIdentity("com.example.extension")
        XCTAssertEqual(ExtensionsRoute.installed(id), ExtensionsRoute.installed(id))
    }

    func testMarketplaceInstallPresentationDistinguishesInstallUpdateAndInstalled() throws {
        let latest = try XCTUnwrap(ExtensionVersion("2.0.0"))
        let old = try XCTUnwrap(ExtensionVersion("1.0.0"))

        XCTAssertEqual(
            MarketplaceInstallPresentation.resolve(
                latestVersion: latest,
                installedVersion: nil,
                compatibility: .compatible,
                trust: .trusted,
                operation: nil
            ),
            MarketplaceInstallPresentation(title: "Get", isEnabled: true)
        )
        XCTAssertEqual(
            MarketplaceInstallPresentation.resolve(
                latestVersion: latest,
                installedVersion: old,
                compatibility: .compatible,
                trust: .trusted,
                operation: nil
            ).title,
            "Update"
        )
        XCTAssertFalse(
            MarketplaceInstallPresentation.resolve(
                latestVersion: latest,
                installedVersion: latest,
                compatibility: .compatible,
                trust: .trusted,
                operation: nil
            ).isEnabled
        )
    }

    func testLocalMarketplaceSamplesCannotBeInstalled() {
        XCTAssertFalse(MarketplaceSample.samples.isEmpty)
        XCTAssertTrue(MarketplaceSample.samples.allSatisfy { !$0.allowsInstallation })
    }

    private func makeSignedCatalog() throws -> (
        data: Data,
        configuration: MarketplaceCatalogConfiguration,
        now: Date
    ) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let date = ISO8601DateFormatter()
        let releaseID = "11111111-1111-1111-1111-111111111111"
        let release: [String: Any] = [
            "releaseID": releaseID,
            "version": "1.2.0",
            "sha256": String(repeating: "a", count: 64),
            "size": 1024,
            "manifestSHA256": String(repeating: "b", count: 64),
            "teamIdentifier": "TEAM123456",
            "notarized": false,
            "stapled": false,
            "signerType": "appleDevelopment",
            "trustBadges": ["reviewedSafe"],
            "artifactKind": "app-extension",
            "providerBundleIdentifier": "com.example.provider",
            "extensionBundleIdentifier": "com.example.provider.extension",
            "extensionPointIdentifier": "com.apple.SwiftUI.ExtensionKitExtension",
            "capabilities": ["open-destination"],
            "entryPoints": [[
                "id": "com.example.extension.main",
                "kind": "open-destination",
                "metadata": [:],
            ]],
            "permissions": [],
            "hostActions": ["open-destination"],
            "compatibility": [
                "minimumMacOSVersion": "26.0.0",
                "supportedHostVersions": ["minimum": "2.0.0", "maximum": "3.0.0"],
                "supportedSDKVersions": ["minimum": "1.0.0", "maximum": "2.0.0"],
                "apiVersion": "1.2.0",
                "protocolVersions": ["minimum": 1, "maximum": 1],
                "supportedArchitectures": ["arm64", "x86_64"],
            ],
            "publishedAt": date.string(from: now.addingTimeInterval(-60)),
            "downloadPath": "/v1/releases/\(releaseID)/download",
        ]
        let payload = try JSONSerialization.data(withJSONObject: [
            "apiVersion": "1",
            "revision": "revision-1",
            "generatedAt": date.string(from: now.addingTimeInterval(-60)),
            "expiresAt": date.string(from: now.addingTimeInterval(3600)),
            "entries": [[
                "id": "com.example.extension",
                "displayName": "Example",
                "summary": "An example extension.",
                "iconSystemName": "puzzlepiece.extension",
                "publisher": [
                    "id": "22222222-2222-2222-2222-222222222222",
                    "displayName": "Example Publisher",
                    "verified": true,
                ],
                "latest": release,
                "versions": [release],
            ]],
        ], options: [.sortedKeys])
        let privateKey = Curve25519.Signing.PrivateKey()
        let signature = try privateKey.signature(
            for: Data("NotchKit-Hub-Catalog-v1\0".utf8) + payload
        )
        let envelope = try JSONSerialization.data(withJSONObject: [
            "keyID": "test-key",
            "payload": payload.base64EncodedString(),
            "signature": signature.base64EncodedString(),
        ], options: [.sortedKeys])
        return (
            envelope,
            MarketplaceCatalogConfiguration(
                catalogURL: URL(string: "https://hub.example/catalog")!,
                keyID: "test-key",
                publicKey: privateKey.publicKey.rawRepresentation
            ),
            now
        )
    }
}
