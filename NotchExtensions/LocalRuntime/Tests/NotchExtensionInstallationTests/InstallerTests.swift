import Foundation
import CryptoKit
import NotchExtensionInstallation
import NotchExtensionSDK
import XCTest

final class InstallerTests: XCTestCase {
    func testInstallCommitsFilesRecordAndRegistration() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let root = workspace.appendingPathComponent("managed")
        let service = FakeRegistrationService()
        let store = FailingStore()
        let installer = makeInstaller(root: root, source: source, service: service, store: store)
        let record = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored.notchkitextension"))
        XCTAssertEqual(record.signature.teamIdentifier, "TEAM")
        XCTAssertEqual(record.manifestSHA256.count, 64)
        XCTAssertEqual(record.declaredPermissions, [.camera(usageDescriptionKey: "NSCameraUsageDescription")])
        XCTAssertEqual(record.declaredHostActions, [.openDestination])
        XCTAssertFalse(record.desiredEnabled)
        XCTAssertEqual(record.systemAuthorityStatus, .unknown)
        XCTAssertEqual(store.snapshot.records, [record])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(record.relativeInstallPath).path))
        XCTAssertEqual(service.registered.count, 1)
    }

    func testRejectsProviderAndExtensionFromDifferentTeams() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "A", extensionTeam: "B"),
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore()
        )
        do {
            _ = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
            XCTFail("Expected install to fail")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .teamMismatch) }
    }

    func testRejectsUpdateSignedByDifferentTeam() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let store = FailingStore()
        _ = try await makeInstaller(root: workspace.appendingPathComponent("managed"), source: source, service: FakeRegistrationService(), store: store)
            .install(archiveURL: workspace.appendingPathComponent("one"))
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "OTHER"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store
        )
        do {
            _ = try await installer.install(archiveURL: workspace.appendingPathComponent("two"))
            XCTFail("Expected update to fail")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .updateTeamMismatch) }
    }

    func testUpdatePreservesInstallTimeAndDesiredEnabled() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let root = workspace.appendingPathComponent("managed")
        let store = FailingStore()
        let first = TransactionalExtensionInstaller(
            rootURL: root,
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store,
            now: { Date(timeIntervalSince1970: 100) }
        )
        _ = try await first.install(archiveURL: workspace.appendingPathComponent("one"))
        store.snapshot.records[0].desiredEnabled = true
        let update = TransactionalExtensionInstaller(
            rootURL: root,
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store,
            now: { Date(timeIntervalSince1970: 200) }
        )
        let record = try await update.install(archiveURL: workspace.appendingPathComponent("two"))
        XCTAssertEqual(record.installedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(record.updatedAt, Date(timeIntervalSince1970: 200))
        XCTAssertTrue(record.desiredEnabled)
    }

    func testExplicitInstallAndUpdateOperationsRejectWrongExistingState() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let installer = makeInstaller(
            root: workspace.appendingPathComponent("managed"),
            source: source,
            service: FakeRegistrationService(),
            store: FailingStore()
        )
        let archive = workspace.appendingPathComponent("archive.notchkitextension")
        try Data().write(to: archive)

        do {
            _ = try await installer.install(.init(archiveURL: archive, operation: .update, trustPolicy: .localDeveloper))
            XCTFail("Expected update without an install to fail")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .operationMismatch) }
        _ = try await installer.install(.init(archiveURL: archive, operation: .install, trustPolicy: .localDeveloper))
        do {
            _ = try await installer.install(.init(archiveURL: archive, operation: .install, trustPolicy: .localDeveloper))
            XCTFail("Expected duplicate install to fail")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .operationMismatch) }
    }

    func testMarketplaceInstallBindsReceiptArchivePackageSignatureAndEvidence() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let manifestData = try makeExtractedPackage(at: source, source: .marketplace)
        let archive = workspace.appendingPathComponent("release.notchkitextension")
        let archiveData = Data("authenticated archive".utf8)
        try archiveData.write(to: archive)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let receipt = try marketplaceReceipt(
            archiveData: archiveData,
            timestamp: timestamp,
            manifestData: manifestData
        )
        let store = FailingStore()
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store,
            now: { timestamp }
        )

        let record = try await installer.install(.init(
            archiveURL: archive,
            operation: .install,
            trustPolicy: .marketplace(receipt: receipt)
        ))
        XCTAssertEqual(record.origin, .marketplace)
        XCTAssertEqual(record.marketplaceReceipt, receipt)
    }

    func testMarketplaceInstallRejectsManifestDigestMismatch() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source, source: .marketplace)
        let archive = workspace.appendingPathComponent("release.notchkitextension")
        let archiveData = Data("authenticated archive".utf8)
        try archiveData.write(to: archive)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore(),
            now: { timestamp }
        )

        do {
            _ = try await installer.install(.init(
                archiveURL: archive,
                operation: .install,
                trustPolicy: .marketplace(receipt: try marketplaceReceipt(
                    archiveData: archiveData,
                    timestamp: timestamp,
                    manifestData: Data("different manifest".utf8)
                ))
            ))
            XCTFail("Expected manifest digest mismatch")
        } catch {
            XCTAssertEqual(error as? ExtensionInstallerError, .marketplaceReceiptMismatch)
        }
    }

    func testMarketplaceInstallRejectsArchiveDigestMismatchBeforeExtraction() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let archive = workspace.appendingPathComponent("release.notchkitextension")
        let archiveData = Data("tampered".utf8)
        try archiveData.write(to: archive)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        var receipt = try marketplaceReceipt(archiveData: archiveData, timestamp: timestamp)
        receipt = MarketplaceReleaseReceipt(
            releaseIdentifier: receipt.releaseIdentifier,
            extensionIdentity: receipt.extensionIdentity,
            extensionVersion: receipt.extensionVersion,
            providerBundleIdentifier: receipt.providerBundleIdentifier,
            extensionBundleIdentifiers: receipt.extensionBundleIdentifiers,
            teamIdentifier: receipt.teamIdentifier,
            archiveSHA256: String(repeating: "0", count: 64),
            archiveByteCount: receipt.archiveByteCount,
            compatibility: receipt.compatibility,
            revocation: receipt.revocation
        )
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore(),
            now: { timestamp }
        )
        do {
            _ = try await installer.install(.init(
                archiveURL: archive,
                operation: .install,
                trustPolicy: .marketplace(receipt: receipt)
            ))
            XCTFail("Expected digest mismatch")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .archiveDigestMismatch) }
    }

    func testMarketplaceInstallAllowsAppleDevelopmentSignatureAfterHubReview() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source, source: .marketplace)
        let archive = workspace.appendingPathComponent("release.notchkitextension")
        let archiveData = Data("authenticated archive".utf8)
        try archiveData.write(to: archive)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM", isDeveloperID: false),
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore(),
            now: { timestamp }
        )
        let installed = try await installer.install(.init(
            archiveURL: archive,
            operation: .install,
            trustPolicy: .marketplace(receipt: try marketplaceReceipt(
                archiveData: archiveData,
                timestamp: timestamp
            ))
        ))
        XCTAssertEqual(installed.origin, .marketplace)
        XCTAssertEqual(installed.signature.teamIdentifier, "TEAM")
    }

    func testUpdateRetainsPreviousReleaseAndManualRollbackSwapsReleases() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstSource = workspace.appendingPathComponent("first")
        let secondSource = workspace.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: firstSource, version: "1.2.3")
        _ = try makeExtractedPackage(at: secondSource, version: "2.0.0")
        let root = workspace.appendingPathComponent("managed")
        let store = FailingStore()
        _ = try await makeInstaller(root: root, source: firstSource, service: FakeRegistrationService(), store: store)
            .install(archiveURL: workspace.appendingPathComponent("one"))
        let updater = makeInstaller(root: root, source: secondSource, service: FakeRegistrationService(), store: store)
        let updated = try await updater.install(archiveURL: workspace.appendingPathComponent("two"))

        XCTAssertEqual(updated.extensionVersion, ExtensionVersion("2.0.0"))
        XCTAssertEqual(updated.previousRelease?.extensionVersion, ExtensionVersion("1.2.3"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("RetainedReleases/com.example.feature.timer").path))

        let rolledBack = try await updater.rollback(id: updated.id)
        XCTAssertEqual(rolledBack.extensionVersion, ExtensionVersion("1.2.3"))
        XCTAssertEqual(rolledBack.previousRelease?.extensionVersion, ExtensionVersion("2.0.0"))
    }

    func testMarketplaceRollbackRequiresFreshEvidenceForRetainedRelease() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstSource = workspace.appendingPathComponent("first")
        let secondSource = workspace.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: firstSource, version: "1.2.3", source: .marketplace)
        _ = try makeExtractedPackage(at: secondSource, version: "2.0.0", source: .marketplace)
        let firstData = Data("release one".utf8)
        let secondData = Data("release two".utf8)
        let firstArchive = workspace.appendingPathComponent("one.notchkitextension")
        let secondArchive = workspace.appendingPathComponent("two.notchkitextension")
        try firstData.write(to: firstArchive)
        try secondData.write(to: secondArchive)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let firstReceipt = try marketplaceReceipt(archiveData: firstData, timestamp: timestamp)
        let secondReceipt = try marketplaceReceipt(
            archiveData: secondData,
            timestamp: timestamp,
            releaseIdentifier: "release-2",
            version: "2.0.0"
        )
        let root = workspace.appendingPathComponent("managed")
        let store = FailingStore()
        let firstInstaller = TransactionalExtensionInstaller(
            rootURL: root,
            archiveValidator: CopyingArchiveValidator(source: firstSource),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store,
            now: { timestamp }
        )
        _ = try await firstInstaller.install(.init(
            archiveURL: firstArchive,
            operation: .install,
            trustPolicy: .marketplace(receipt: firstReceipt)
        ))
        let updater = TransactionalExtensionInstaller(
            rootURL: root,
            archiveValidator: CopyingArchiveValidator(source: secondSource),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: NoOpExtensionRegistrationService(),
            store: store,
            now: { timestamp }
        )
        let updated = try await updater.install(.init(
            archiveURL: secondArchive,
            operation: .update,
            trustPolicy: .marketplace(receipt: secondReceipt)
        ))

        do {
            _ = try await updater.rollback(id: updated.id)
            XCTFail("Expected fresh marketplace evidence")
        } catch {
            XCTAssertEqual(error as? ExtensionInstallerError, .staleMarketplaceEvidence)
        }
        let rolledBack = try await updater.rollback(id: updated.id, marketplaceReceipt: firstReceipt)
        XCTAssertEqual(rolledBack.extensionVersion, ExtensionVersion("1.2.3"))
        XCTAssertEqual(rolledBack.marketplaceReceipt, firstReceipt)
    }

    func testRevalidatesPackageAndSignaturesAfterMove() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let packages = CountingPackageValidator()
        let signatures = CountingSignatureValidator()
        let installer = TransactionalExtensionInstaller(
            rootURL: workspace.appendingPathComponent("managed"),
            archiveValidator: CopyingArchiveValidator(source: source),
            packageValidator: packages,
            signatureValidator: signatures,
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore()
        )
        _ = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
        XCTAssertEqual(packages.validatedRoots.count, 2)
        XCTAssertEqual(signatures.validatedURLs.count, 4)
        XCTAssertTrue(packages.validatedRoots[1].path.contains("/Extensions/com.example.feature.timer"))
    }

    func testRecordFailureRollsBackNewInstall() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let store = FailingStore()
        store.failSave = true
        let root = workspace.appendingPathComponent("managed")
        let service = FakeRegistrationService()
        let installer = makeInstaller(root: root, source: source, service: service, store: store)
        do {
            _ = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
            XCTFail("Expected install to fail")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Extensions/com.example.feature.timer").path))
        XCTAssertEqual(service.unregistered.count, 1)
    }

    func testAsyncRegistrationFailureRollsBackNewInstall() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let root = workspace.appendingPathComponent("managed")
        let service = FakeRegistrationService()
        service.registrationError = TestError.expected
        let installer = makeInstaller(root: root, source: source, service: service, store: FailingStore())

        do {
            _ = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
            XCTFail("Expected registration to fail")
        } catch {
            XCTAssertEqual(error as? TestError, .expected)
        }

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Extensions/com.example.feature.timer").path
        ))
        XCTAssertEqual(service.unregistered.count, 1)
    }

    func testUninstallRemovesManagedInstallAndRecord() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: source)
        let store = FailingStore()
        let service = FakeRegistrationService()
        let installer = makeInstaller(root: workspace.appendingPathComponent("managed"), source: source, service: service, store: store)
        let record = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
        try await installer.uninstall(id: record.id)
        XCTAssertTrue(store.snapshot.records.isEmpty)
        XCTAssertEqual(service.unregistered.count, 1)
    }

    func testUninstallStoreFailureRestoresActiveAndRetainedReleases() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstSource = workspace.appendingPathComponent("first")
        let secondSource = workspace.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondSource, withIntermediateDirectories: true)
        _ = try makeExtractedPackage(at: firstSource, version: "1.2.3")
        _ = try makeExtractedPackage(at: secondSource, version: "2.0.0")
        let root = workspace.appendingPathComponent("managed")
        let store = FailingStore()
        let service = FakeRegistrationService()
        _ = try await makeInstaller(root: root, source: firstSource, service: service, store: store)
            .install(archiveURL: workspace.appendingPathComponent("one"))
        let updater = makeInstaller(root: root, source: secondSource, service: service, store: store)
        let updated = try await updater.install(archiveURL: workspace.appendingPathComponent("two"))
        store.failSave = true

        do {
            try await updater.uninstall(id: updated.id)
            XCTFail("Expected record persistence failure")
        } catch {
            XCTAssertEqual(error as? TestError, .expected)
        }

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Extensions/com.example.feature.timer").path
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("RetainedReleases/com.example.feature.timer").path
        ))
        XCTAssertEqual(store.snapshot.records.first?.extensionVersion, ExtensionVersion("2.0.0"))
    }

    func testUninstallRefusesPersistedUnmanagedPath() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try ExtensionIdentity("com.example.feature.timer")
        let record = InstalledExtensionRecord(
            id: id,
            extensionVersion: ExtensionVersion("1.2.3")!,
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifiers: [id.rawValue],
            relativeInstallPath: "../../victim",
            manifestSHA256: String(repeating: "a", count: 64),
            declaredPermissions: [],
            declaredHostActions: [],
            signature: InstalledCodeSignature(teamIdentifier: "TEAM", providerDesignatedRequirement: "r", extensionDesignatedRequirements: [:]),
            installedAt: Date(),
            updatedAt: Date(),
            desiredEnabled: false,
            localStatus: .installed
        )
        let installer = TransactionalExtensionInstaller(
            rootURL: root,
            registrationService: NoOpExtensionRegistrationService(),
            store: FailingStore(.init(records: [record]))
        )
        do {
            try await installer.uninstall(id: id)
            XCTFail("Expected uninstall to fail")
        } catch { XCTAssertEqual(error as? ExtensionInstallerError, .unmanagedInstallPath) }
    }

    func testInstallRefusesManagedDirectorySymlinkEscape() async throws {
        let workspace = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let source = workspace.appendingPathComponent("source")
        let root = workspace.appendingPathComponent("managed")
        let outside = workspace.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Extensions"),
            withDestinationURL: outside
        )
        _ = try makeExtractedPackage(at: source)
        let installer = makeInstaller(
            root: root,
            source: source,
            service: FakeRegistrationService(),
            store: FailingStore()
        )

        do {
            _ = try await installer.install(archiveURL: workspace.appendingPathComponent("ignored"))
            XCTFail("Expected symlink escape rejection")
        } catch {
            XCTAssertEqual(error as? ExtensionInstallerError, .unmanagedInstallPath)
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    private func makeInstaller(
        root: URL,
        source: URL,
        service: FakeRegistrationService,
        store: FailingStore
    ) -> TransactionalExtensionInstaller {
        TransactionalExtensionInstaller(
            rootURL: root,
            archiveValidator: CopyingArchiveValidator(source: source),
            signatureValidator: FakeSignatureValidator(team: "TEAM"),
            registrationService: service,
            store: store,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
    }

    private func marketplaceReceipt(
        archiveData: Data,
        timestamp: Date,
        releaseIdentifier: String = "release-1",
        version: String = "1.2.3",
        manifestData: Data? = nil
    ) throws -> MarketplaceReleaseReceipt {
        MarketplaceReleaseReceipt(
            releaseIdentifier: releaseIdentifier,
            extensionIdentity: try ExtensionIdentity("com.example.feature.timer"),
            extensionVersion: ExtensionVersion(version)!,
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifiers: ["com.example.provider.TimerExtension"],
            teamIdentifier: "TEAM",
            archiveSHA256: SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined(),
            archiveByteCount: UInt64(archiveData.count),
            compatibility: MarketplaceCompatibilityEvidence(
                evaluatedAt: timestamp,
                hostVersion: ExtensionVersion("1.0.0")!,
                sdkVersion: .current,
                macOSVersion: ExtensionVersion("26.0.0")!,
                protocolVersion: 1,
                architecture: .arm64
            ),
            revocation: MarketplaceRevocationEvidence(checkedAt: timestamp, status: .notRevoked),
            manifestSHA256: manifestData.map {
                SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()
            }
        )
    }
}
