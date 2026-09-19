import AppKit
import Combine
import CryptoKit
import Foundation
import NotchExtensionInstallation
import NotchExtensionRuntime
import NotchExtensionSDK
import NotchExtensionWire
import SwiftUI

struct LocalExtensionPackagePreview: Identifiable, Sendable {
    var id: ExtensionIdentity { manifest.metadata.id }
    let archiveURL: URL
    let manifest: ExtensionPackageManifest
    let signerTeamIdentifier: String

    var isUpdate: Bool = false
}

struct InstalledLocalExtension: Identifiable {
    let record: InstalledExtensionRecord
    let manifest: ExtensionPackageManifest?
    let assetsURL: URL?
    let validationError: String?
    let isDiscovered: Bool

    var id: ExtensionIdentity { record.id }
    var displayName: String { manifest?.metadata.displayName ?? record.id.rawValue }
}

/// Launching a provider application is the public registration mechanism for
/// independently delivered app extensions. Unregistration never terminates a
/// different copy of an application that happens to share its bundle ID.
struct WorkspaceExtensionRegistrationService: ExtensionRegistrationServicing, @unchecked Sendable {
    let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func register(providerAt url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        _ = try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: url, configuration: configuration) { application, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: application) }
            }
        } as NSRunningApplication?
    }

    func unregister(providerAt url: URL) async throws {
        let expected = url.resolvingSymlinksInPath().standardizedFileURL
        for application in workspace.runningApplications {
            guard application.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == expected else { continue }
            application.terminate()
        }
    }
}

@MainActor
final class LocalExtensionCoordinator: ObservableObject {
    @Published private(set) var installed: [InstalledLocalExtension] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var disabledCount = 0
    @Published private(set) var unapprovedCount = 0
    @Published private(set) var hasManagedLocationAccess: Bool

    let rootURL: URL

    private static let managedLocationBookmarkKey = "localExtensions.managedLocationBookmark.v1"
    private let manager: ExtensionManager
    private let contributions: ContributionStore
    private let store: any InstalledExtensionStore
    private let installer: TransactionalExtensionInstaller
    private let requiresManagedLocationAccess: Bool
    private var securityScopedRootURL: URL?
    private var discoveredIDs = Set<String>()
    private var publishedIDs = Set<ExtensionIdentity>()
    private var nativeRuntime: AnyObject?

    init(
        manager: ExtensionManager,
        contributions: ContributionStore,
        rootURL: URL? = nil,
        registrationService: any ExtensionRegistrationServicing = WorkspaceExtensionRegistrationService()
    ) {
        self.manager = manager
        self.contributions = contributions
        self.rootURL = rootURL ?? Self.defaultRootURL
        requiresManagedLocationAccess = rootURL == nil && !TestHostPolicy.isActive
        if requiresManagedLocationAccess,
           let scopedURL = Self.restoreManagedLocationAccess(expectedRootURL: self.rootURL) {
            securityScopedRootURL = scopedURL
            hasManagedLocationAccess = true
        } else {
            hasManagedLocationAccess = !requiresManagedLocationAccess
        }
        let store = JSONInstalledExtensionStore(rootURL: self.rootURL)
        self.store = store
        self.installer = TransactionalExtensionInstaller(
            rootURL: self.rootURL,
            registrationService: registrationService,
            store: store
        )
    }

    deinit {
        securityScopedRootURL?.stopAccessingSecurityScopedResource()
    }

    static var defaultRootURL: URL {
        if TestHostPolicy.isActive {
            return TestHostPolicy.isolationRoot.appendingPathComponent("LocalExtensions", isDirectory: true)
        }
        return liveRootURL
    }

    static var liveRootURL: URL {
        let homeURL: URL
        if let homePath = getpwuid(getuid())?.pointee.pw_dir {
            homeURL = URL(fileURLWithPath: String(cString: homePath), isDirectory: true)
        } else {
            homeURL = FileManager.default.homeDirectoryForCurrentUser
        }
        return homeURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(NotchKitIdentity.shelfDirectoryName, isDirectory: true)
            .appendingPathComponent("LocalExtensions", isDirectory: true)
    }

    func authorizeManagedLocation(at selectedURL: URL) throws {
        let selected = selectedURL.resolvingSymlinksInPath().standardizedFileURL
        let expected = rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard selected == expected else {
            throw LocalExtensionManagedLocationError.wrongDirectory(expected.path)
        }
        let bookmark = try selectedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        var stale = false
        let resolved = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard resolved.resolvingSymlinksInPath().standardizedFileURL == expected,
              resolved.startAccessingSecurityScopedResource()
        else { throw LocalExtensionManagedLocationError.accessDenied }

        securityScopedRootURL?.stopAccessingSecurityScopedResource()
        securityScopedRootURL = resolved
        UserDefaults.standard.set(bookmark, forKey: Self.managedLocationBookmarkKey)
        hasManagedLocationAccess = true
    }

    private static func restoreManagedLocationAccess(expectedRootURL: URL) -> URL? {
        guard let bookmark = UserDefaults.standard.data(forKey: managedLocationBookmarkKey) else {
            return nil
        }
        var stale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ),
            resolved.resolvingSymlinksInPath().standardizedFileURL
                == expectedRootURL.resolvingSymlinksInPath().standardizedFileURL,
            resolved.startAccessingSecurityScopedResource()
        else {
            UserDefaults.standard.removeObject(forKey: managedLocationBookmarkKey)
            return nil
        }
        if stale, let refreshed = try? resolved.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(refreshed, forKey: managedLocationBookmarkKey)
        }
        return resolved
    }

    func start() {
        refreshInventory()
        guard !TestHostPolicy.isActive else { return }
        if #available(macOS 26.0, *) {
            let runtime = LocalExtensionNativeRuntime(coordinator: self)
            nativeRuntime = runtime
            Task { await runtime.start() }
        }
    }

    /// Reads only the selected package and an ephemeral staging directory. It
    /// performs the same archive, manifest, layout, and signature checks as an
    /// install and always removes staging before returning.
    nonisolated static func previewPackage(at archiveURL: URL) async throws -> LocalExtensionPackagePreview {
        try await Task.detached(priority: .userInitiated) {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("notchkit-preview-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            try ZIPPackageArchiveValidator().validateAndExtract(archiveURL: archiveURL, to: staging)
            let package = try DefaultExtractedPackageValidator().validate(packageRootURL: staging)
            let validator = SecurityCodeSignatureValidator()
            let provider = try validator.validateCode(at: package.providerURL)
            for extensionURL in package.extensionURLs {
                let signature = try validator.validateCode(at: extensionURL)
                guard signature.teamIdentifier == provider.teamIdentifier else {
                    throw ExtensionInstallerError.teamMismatch
                }
            }
            return LocalExtensionPackagePreview(
                archiveURL: archiveURL,
                manifest: package.packageManifest,
                signerTeamIdentifier: provider.teamIdentifier
            )
        }.value
    }

    func install(_ preview: LocalExtensionPackagePreview) async throws {
        guard hasManagedLocationAccess else {
            throw LocalExtensionManagedLocationError.accessRequired
        }
        _ = try await installer.install(archiveURL: preview.archiveURL)
        await refresh()
    }

    func uninstall(_ id: ExtensionIdentity) async throws {
        try await installer.uninstall(id: id)
        contributions.removeContributions(for: id)
        manager.removeExternalEnabledState(for: id)
        publishedIDs.remove(id)
        await refresh()
    }

    func setDesiredEnabled(_ enabled: Bool, for id: ExtensionIdentity) {
        do {
            var snapshot = try store.load()
            guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { return }
            snapshot.records[index].desiredEnabled = enabled
            try store.save(snapshot)
            refreshInventory()
            reconcilePublishedContributions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        refreshInventory()
        if #available(macOS 26.0, *), let runtime = nativeRuntime as? LocalExtensionNativeRuntime {
            await runtime.refresh()
        } else {
            reconcilePublishedContributions()
        }
    }

    func clearError() { errorMessage = nil }

    private func refreshInventory() {
        do {
            let snapshot = try store.load()
            installed = snapshot.records.map(loadInstalledRecord).sorted {
                $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
            }
            errorMessage = nil
        } catch {
            installed = []
            errorMessage = error.localizedDescription
        }
    }

    private func loadInstalledRecord(_ record: InstalledExtensionRecord) -> InstalledLocalExtension {
        let expected = "Extensions/\(record.id.rawValue)"
        guard record.relativeInstallPath == expected else {
            return InstalledLocalExtension(
                record: record,
                manifest: nil,
                assetsURL: nil,
                validationError: "The installation record points outside its managed location.",
                isDiscovered: false
            )
        }
        do {
            let path = rootURL.appendingPathComponent(expected, isDirectory: true)
            let package = try DefaultExtractedPackageValidator().validate(packageRootURL: path)
            guard package.manifest.id == record.id,
                  package.providerBundleIdentifier == record.providerBundleIdentifier,
                  Set(package.extensionBundleIdentifiers) == Set(record.extensionBundleIdentifiers),
                  SHA256.hash(data: package.manifestData).map({ String(format: "%02x", $0) }).joined()
                    == record.manifestSHA256
            else { throw ExtensionInstallerError.installedCopyMismatch }
            return InstalledLocalExtension(
                record: record,
                manifest: package.packageManifest,
                assetsURL: LocalExtensionAssetLoader.validatedAssetsRoot(
                    providerURL: package.providerURL
                ),
                validationError: nil,
                isDiscovered: discoveredIDs.contains(record.id.rawValue)
            )
        } catch {
            return InstalledLocalExtension(
                record: record,
                manifest: nil,
                assetsURL: nil,
                validationError: error.localizedDescription,
                isDiscovered: false
            )
        }
    }

    func applyDiscovery(
        matchedExtensionIDs: Set<ExtensionIdentity>,
        disabledCount: Int,
        unapprovedCount: Int
    ) {
        do {
            var snapshot = try store.load()
            for index in snapshot.records.indices {
                snapshot.records[index].systemAuthorityStatus = matchedExtensionIDs.contains(
                    snapshot.records[index].id
                ) ? .approved : .unknown
            }
            try store.save(snapshot)
            discoveredIDs = Set(matchedExtensionIDs.map(\.rawValue))
            self.disabledCount = disabledCount
            self.unapprovedCount = unapprovedCount
            refreshInventory()
            reconcilePublishedContributions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reconcilePublishedContributions() {
        let valid = installed.filter {
            $0.manifest != nil && $0.record.desiredEnabled && $0.isDiscovered
        }
        let validIDs = Set(valid.map(\.id))
        for id in publishedIDs.subtracting(validIDs) {
            contributions.removeContributions(for: id)
            manager.removeExternalEnabledState(for: id)
        }
        for item in installed {
            manager.setExternalEnabled(validIDs.contains(item.id), for: item.id)
        }
        for item in valid {
            guard let manifest = item.manifest else { continue }
            do {
                try publish(manifest)
            } catch {
                contributions.removeContributions(for: item.id)
                manager.setExternalEnabled(false, for: item.id)
                errorMessage = "\(item.displayName): \(error.localizedDescription)"
            }
        }
        publishedIDs = validIDs
    }

    private func publish(_ manifest: ExtensionPackageManifest) throws {
        let metadata = manifest.metadata
        let descriptors = Dictionary(uniqueKeysWithValues: manifest.entryPoints.map { ($0.id, $0) })
        let open = metadata.entryPoints(of: .openDestination).compactMap { entry -> NotchOpenDestination? in
            guard let descriptor = descriptors[entry.id] else { return nil }
            return NotchOpenDestination(
                id: DestinationID(entry.id),
                title: entry.metadata["title"] ?? metadata.displayName,
                iconSystemName: entry.metadata["iconSystemName"] ?? metadata.iconSystemName,
                order: Int(entry.metadata["order"] ?? "") ?? 500,
                isAvailable: { true },
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return self.view(
                        for: descriptor,
                        manifest: manifest,
                        assetsURL: itemAssetsURL(for: metadata.id)
                    )
                }
            )
        }
        let closed = metadata.entryPoints(of: .closedNotchContribution).compactMap { entry -> ClosedNotchContribution? in
            guard let descriptor = descriptors[entry.id], descriptor.presentationMode == .declarative else {
                return nil
            }
            let region = ClosedNotchRegion(rawValue: entry.metadata["region"] ?? "") ?? .exclusion
            let priority = Int(entry.metadata["priority"] ?? "") ?? 0
            return ClosedNotchContribution(
                id: ContributionID(entry.id),
                extensionID: metadata.id,
                region: region,
                priority: priority,
                tieBreaker: entry.id,
                isAvailable: { _ in true },
                makeView: { [weak self] in
                    guard let self else { return AnyView(EmptyView()) }
                    return self.view(
                        for: descriptor,
                        manifest: manifest,
                        assetsURL: itemAssetsURL(for: metadata.id)
                    )
                }
            )
        }
        try contributions.set(open: open, closed: closed, settings: [], for: metadata.id)
    }

    private func view(
        for entryPoint: ExtensionPackageEntryPoint,
        manifest: ExtensionPackageManifest,
        assetsURL: URL?
    ) -> AnyView {
        guard #available(macOS 26.0, *), let runtime = nativeRuntime as? LocalExtensionNativeRuntime else {
            return AnyView(Text("Local extensions require macOS 26 or later."))
        }
        return runtime.view(for: entryPoint, manifest: manifest, assetsURL: assetsURL)
    }

    private func itemAssetsURL(for id: ExtensionIdentity) -> URL? {
        installed.first(where: { $0.id == id })?.assetsURL
    }
}

enum LocalExtensionManagedLocationError: LocalizedError {
    case accessRequired
    case accessDenied
    case wrongDirectory(String)

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            "Allow access to the managed local-extension folder before installing."
        case .accessDenied:
            "NotchKit could not retain access to the managed local-extension folder."
        case let .wrongDirectory(path):
            "Choose the NotchKit managed local-extension folder at \(path)."
        }
    }
}

enum LocalExtensionAssetLoader {
    static func validatedAssetsRoot(
        providerURL: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let provider = providerURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = providerURL
            .appendingPathComponent("Contents/Resources/NotchKitExtension/assets", isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard contains(candidate, in: provider) else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return candidate
    }

    static func image(
        named resourceName: String,
        assetsRoot: URL?,
        fileManager: FileManager = .default
    ) -> NSImage? {
        guard let candidate = assetURL(
            named: resourceName,
            assetsRoot: assetsRoot,
            fileManager: fileManager
        ) else { return nil }
        return NSImage(contentsOf: candidate)
    }

    static func assetURL(
        named resourceName: String,
        assetsRoot: URL?,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let assetsRoot,
              !resourceName.isEmpty,
              !resourceName.hasPrefix("/"),
              !resourceName.contains("\\"),
              !resourceName.split(separator: "/", omittingEmptySubsequences: false).contains("..")
        else { return nil }
        let root = assetsRoot.resolvingSymlinksInPath().standardizedFileURL
        let candidate = assetsRoot
            .appendingPathComponent(resourceName, isDirectory: false)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard contains(candidate, in: root), fileManager.isReadableFile(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        candidate.path.hasPrefix(root.path + "/")
    }
}
