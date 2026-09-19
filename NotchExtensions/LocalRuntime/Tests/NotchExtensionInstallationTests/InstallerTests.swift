import Foundation
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
}
