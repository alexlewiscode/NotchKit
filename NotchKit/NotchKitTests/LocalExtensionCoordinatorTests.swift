import AppKit
import NotchExtensionInstallation
import NotchExtensionRuntime
import NotchExtensionSDK
import XCTest
@testable import NotchKit

@MainActor
final class LocalExtensionCoordinatorTests: XCTestCase {
    private func makeRecord(
        id: ExtensionIdentity,
        authority: SystemAuthorityStatus = .unknown
    ) -> InstalledExtensionRecord {
        InstalledExtensionRecord(
            id: id,
            extensionVersion: ExtensionVersion(major: 1, minor: 2, patch: 3),
            providerBundleIdentifier: "com.example.provider",
            extensionBundleIdentifiers: ["com.example.provider.extension"],
            relativeInstallPath: "Extensions/\(id.rawValue)",
            manifestSHA256: "missing",
            declaredPermissions: [],
            declaredHostActions: [],
            signature: InstalledCodeSignature(
                teamIdentifier: "TESTTEAM",
                providerDesignatedRequirement: "identifier com.example.provider",
                extensionDesignatedRequirements: [:]
            ),
            installedAt: Date(),
            updatedAt: Date(),
            desiredEnabled: true,
            localStatus: .installed,
            systemAuthorityStatus: authority
        )
    }

    func testDefaultRootIsInsideTestHostIsolation() {
        XCTAssertTrue(TestHostPolicy.isActive)
        XCTAssertTrue(
            LocalExtensionCoordinator.defaultRootURL.standardizedFileURL.path
                .hasPrefix(TestHostPolicy.isolationRoot.standardizedFileURL.path)
        )
    }

    func testInventorySurvivesMissingManagedArtifactAndDesiredStatePersists() throws {
        let root = TestHostPolicy.isolationRoot
            .appendingPathComponent("local-extension-coordinator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id = try ExtensionIdentity("com.example.local-test")
        let record = makeRecord(id: id)
        let store = JSONInstalledExtensionStore(rootURL: root)
        try store.save(InstalledExtensionSnapshot(records: [record]))

        let registry = ExtensionRegistry(hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0))
        let coordinator = LocalExtensionCoordinator(
            manager: ExtensionManager(registry: registry, store: InMemoryExtensionStateStore()),
            contributions: ContributionStore(),
            rootURL: root,
            registrationService: NoOpExtensionRegistrationService()
        )
        coordinator.start()

        XCTAssertTrue(coordinator.hasManagedLocationAccess)
        XCTAssertEqual(coordinator.installed.map(\.id), [id])
        XCTAssertNotNil(coordinator.installed[0].validationError)
        XCTAssertFalse(coordinator.installed[0].isDiscovered)

        coordinator.setDesiredEnabled(false, for: id)
        XCTAssertFalse(try store.load().records[0].desiredEnabled)
        XCTAssertEqual(coordinator.installed.map(\.id), [id])
    }

    func testManagedLocationAuthorizationRejectsAnotherDirectory() throws {
        let registry = ExtensionRegistry(hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0))
        let coordinator = LocalExtensionCoordinator(
            manager: ExtensionManager(registry: registry, store: InMemoryExtensionStateStore()),
            contributions: ContributionStore(),
            rootURL: LocalExtensionCoordinator.liveRootURL,
            registrationService: NoOpExtensionRegistrationService()
        )

        XCTAssertThrowsError(
            try coordinator.authorizeManagedLocation(at: TestHostPolicy.isolationRoot)
        ) { error in
            guard case LocalExtensionManagedLocationError.wrongDirectory = error else {
                return XCTFail("Expected wrong-directory error, got \(error)")
            }
        }
    }

    func testDiscoveryPersistsApprovedOnlyForExactMatches() throws {
        let root = TestHostPolicy.isolationRoot
            .appendingPathComponent("local-authority-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let matched = try ExtensionIdentity("com.example.matched")
        let unmatched = try ExtensionIdentity("com.example.unmatched")
        let store = JSONInstalledExtensionStore(rootURL: root)
        try store.save(InstalledExtensionSnapshot(records: [
            makeRecord(id: matched),
            makeRecord(id: unmatched, authority: .denied),
        ]))
        let registry = ExtensionRegistry(hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0))
        let coordinator = LocalExtensionCoordinator(
            manager: ExtensionManager(registry: registry, store: InMemoryExtensionStateStore()),
            contributions: ContributionStore(),
            rootURL: root,
            registrationService: NoOpExtensionRegistrationService()
        )

        coordinator.applyDiscovery(
            matchedExtensionIDs: [matched],
            disabledCount: 3,
            unapprovedCount: 2
        )

        let records = Dictionary(uniqueKeysWithValues: try store.load().records.map { ($0.id, $0) })
        XCTAssertEqual(records[matched]?.systemAuthorityStatus, .approved)
        XCTAssertEqual(records[unmatched]?.systemAuthorityStatus, .unknown)
        XCTAssertEqual(coordinator.disabledCount, 3)
        XCTAssertEqual(coordinator.unapprovedCount, 2)
    }

    func testAssetLookupRejectsTraversalAbsolutePathsAndSymlinkEscapes() throws {
        let root = TestHostPolicy.isolationRoot
            .appendingPathComponent("local-assets-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let provider = root.appendingPathComponent("Provider.app", isDirectory: true)
        let assets = provider.appendingPathComponent(
            "Contents/Resources/NotchKitExtension/assets",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let valid = assets.appendingPathComponent("icons/status.png")
        try FileManager.default.createDirectory(
            at: valid.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("asset".utf8).write(to: valid)
        let outside = root.appendingPathComponent("outside.png")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: assets.appendingPathComponent("escaped.png"),
            withDestinationURL: outside
        )

        let validatedRoot = LocalExtensionAssetLoader.validatedAssetsRoot(providerURL: provider)
        XCTAssertEqual(
            LocalExtensionAssetLoader.assetURL(named: "icons/status.png", assetsRoot: validatedRoot),
            valid.standardizedFileURL
        )
        XCTAssertNil(LocalExtensionAssetLoader.assetURL(named: "../outside.png", assetsRoot: validatedRoot))
        XCTAssertNil(LocalExtensionAssetLoader.assetURL(named: outside.path, assetsRoot: validatedRoot))
        XCTAssertNil(LocalExtensionAssetLoader.assetURL(named: "escaped.png", assetsRoot: validatedRoot))
    }

    func testSignedPackageInstallsRegistersAndUninstalls() async throws {
        guard let archivePath = ProcessInfo.processInfo.environment["NOTCHKIT_SIGNED_EXTENSION_PACKAGE"] else {
            throw XCTSkip("Set NOTCHKIT_SIGNED_EXTENSION_PACKAGE to run the signed-package integration test.")
        }
        let preview = try await LocalExtensionCoordinator.previewPackage(
            at: URL(fileURLWithPath: archivePath)
        )
        let root = LocalExtensionCoordinator.liveRootURL
        let store = JSONInstalledExtensionStore(rootURL: root)
        if try store.load().records.contains(where: { $0.id == preview.id }) {
            throw XCTSkip("The sample extension is already installed in the live managed location.")
        }

        let registry = ExtensionRegistry(hostVersion: ExtensionVersion(major: 1, minor: 0, patch: 0))
        let coordinator = LocalExtensionCoordinator(
            manager: ExtensionManager(registry: registry, store: InMemoryExtensionStateStore()),
            contributions: ContributionStore(),
            rootURL: root
        )

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let panel = NSOpenPanel()
        panel.title = "Authorize Signed Extension Integration Test"
        panel.message = "Choose this LocalExtensions folder to test executable installation."
        panel.prompt = "Authorize"
        panel.directoryURL = root
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            throw XCTSkip("Managed-location authorization was cancelled.")
        }
        try coordinator.authorizeManagedLocation(at: selectedURL)

        try await coordinator.install(preview)

        XCTAssertEqual(coordinator.installed.map(\.id), [preview.id])
        XCTAssertNil(coordinator.installed[0].validationError)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root
                .appendingPathComponent("Extensions/\(preview.id.rawValue)/payload/provider.app")
                .path
        ))

        try await coordinator.uninstall(preview.id)

        XCTAssertTrue(coordinator.installed.isEmpty)
    }
}
