import Combine
import Foundation
import NotchExtensionInstallation
import NotchExtensionSDK

@MainActor
final class MarketplaceCatalogCoordinator: ObservableObject {
    enum Phase: Equatable {
        case unavailable
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase
    @Published private(set) var snapshot: MarketplaceCatalogSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isUsingCachedCatalog = false
    @Published private(set) var refreshError: String?
    @Published private(set) var operations: [ExtensionIdentity: String] = [:]

    private let configuration: MarketplaceCatalogConfiguration?
    private let fetcher: any MarketplaceCatalogFetching
    private let cache: any MarketplaceCatalogCaching
    private let revocationHandler: @MainActor @Sendable (Set<String>) -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        configuration: MarketplaceCatalogConfiguration? = .fromBundle(),
        fetcher: any MarketplaceCatalogFetching = URLSessionMarketplaceCatalogFetcher(),
        cache: any MarketplaceCatalogCaching = DiskMarketplaceCatalogCache(),
        revocationHandler: @escaping @MainActor @Sendable (Set<String>) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.fetcher = fetcher
        self.cache = cache
        self.revocationHandler = revocationHandler
        phase = configuration == nil ? .unavailable : .idle
        loadVerifiedCache()
    }

    deinit { refreshTask?.cancel() }

    func refresh() {
        guard #available(macOS 26.0, *) else {
            phase = .failed(MarketplaceCatalogError.unsupportedPlatform.localizedDescription)
            return
        }
        guard let configuration else {
            phase = .unavailable
            return
        }
        refreshTask?.cancel()
        refreshError = nil
        phase = .loading
        let cachedETag = (try? cache.load())?.etag
        refreshTask = Task { [weak self, fetcher, cache, revocationHandler] in
            do {
                let response = try await fetcher.fetchCatalog(
                    at: configuration.catalogURL,
                    etag: cachedETag
                )
                try Task.checkCancellation()
                let verified: MarketplaceCatalogSnapshot
                switch response {
                case let .modified(data, etag):
                    verified = try MarketplaceCatalogVerifier.verify(data, configuration: configuration)
                    try cache.store(MarketplaceCachedCatalog(data: data, etag: etag, verifiedAt: Date()))
                case .notModified:
                    guard let cached = try cache.load() else {
                        throw MarketplaceCatalogError.cacheUnavailable
                    }
                    verified = try MarketplaceCatalogVerifier.verify(cached.data, configuration: configuration)
                }
                guard !Task.isCancelled else { return }
                var revocationError: String?
                do {
                    let feed = try await MarketplaceDistributionClient(
                        configuration: configuration
                    ).revocations()
                    revocationHandler(Set(feed.revocations.map(\.artifactSha256)))
                } catch {
                    revocationError = error.localizedDescription
                }
                self?.snapshot = verified
                self?.lastUpdatedAt = Date()
                self?.isUsingCachedCatalog = false
                self?.refreshError = revocationError
                self?.phase = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                if self?.snapshot != nil {
                    self?.isUsingCachedCatalog = true
                    self?.refreshError = error.localizedDescription
                    self?.phase = .loaded
                } else {
                    self?.phase = .failed(error.localizedDescription)
                }
            }
        }
    }

    func entry(for id: ExtensionIdentity) -> MarketplaceCatalogEntry? {
        snapshot?.entries.first { $0.id == id }
    }

    @available(macOS 26.0, *)
    func install(
        _ entry: MarketplaceCatalogEntry,
        environment: MarketplaceHostEnvironment,
        localExtensions: LocalExtensionCoordinator
    ) async throws {
        guard let configuration, let snapshot, snapshot.expiresAt > Date() else {
            throw MarketplaceCatalogError.expired
        }
        guard MarketplaceReleaseEvaluator.compatibility(of: entry.latest, with: environment) == .compatible,
              MarketplaceReleaseEvaluator.trust(of: entry) == .trusted
        else { throw MarketplaceCatalogError.invalidCatalog }
        guard operations[entry.id] == nil else { return }
        operations[entry.id] = "Verifying"
        defer { operations[entry.id] = nil }

        let client = MarketplaceDistributionClient(configuration: configuration)
        let revocations = try await client.revocations()
        revocationHandler(Set(revocations.revocations.map(\.artifactSha256)))
        guard !revocations.revocations.contains(where: {
            $0.extensionId == entry.id
                && ($0.artifactSha256 == entry.latest.sha256 || $0.version == entry.latest.version)
        }) else { throw ExtensionInstallerError.revokedMarketplaceRelease }
        let authorization = try await client.authorization(for: entry.latest)
        operations[entry.id] = "Downloading"
        let archiveURL = try await MarketplaceArtifactDownloader().download(
            release: entry.latest,
            from: authorization.url
        )
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        operations[entry.id] = "Installing"
        let installed = localExtensions.installed.contains { $0.id == entry.id }
        let timestamp = Date()
        let receipt = MarketplaceReleaseReceipt(
            releaseIdentifier: entry.latest.releaseID.uuidString,
            extensionIdentity: entry.id,
            extensionVersion: entry.latest.version,
            providerBundleIdentifier: entry.latest.providerBundleIdentifier,
            extensionBundleIdentifiers: [entry.latest.extensionBundleIdentifier],
            teamIdentifier: entry.latest.teamIdentifier,
            archiveSHA256: entry.latest.sha256,
            archiveByteCount: UInt64(entry.latest.size),
            compatibility: MarketplaceCompatibilityEvidence(
                evaluatedAt: timestamp,
                hostVersion: environment.hostVersion,
                sdkVersion: ExtensionAPIVersion(
                    major: environment.sdkVersion.major,
                    minor: environment.sdkVersion.minor,
                    patch: environment.sdkVersion.patch
                ),
                macOSVersion: environment.macOSVersion,
                protocolVersion: environment.protocolVersion,
                architecture: environment.architecture
            ),
            revocation: MarketplaceRevocationEvidence(
                checkedAt: timestamp,
                status: .notRevoked
            ),
            catalogRevision: snapshot.revision,
            catalogKeyIdentifier: configuration.keyID,
            publisherIdentifier: entry.publisher.id.uuidString,
            manifestSHA256: entry.latest.manifestSHA256,
            validationPolicyVersion: 1,
            verifiedAt: timestamp
        )
        try await localExtensions.installMarketplace(
            archiveURL: archiveURL,
            receipt: receipt,
            operation: installed ? .update : .install
        )
    }

    @available(macOS 26.0, *)
    func rollback(
        _ item: InstalledLocalExtension,
        environment: MarketplaceHostEnvironment,
        localExtensions: LocalExtensionCoordinator
    ) async throws {
        guard let configuration,
              let previous = item.record.previousRelease,
              let storedReceipt = previous.marketplaceReceipt
        else { throw ExtensionInstallerError.noPreviousRelease }
        let feed = try await MarketplaceDistributionClient(configuration: configuration).revocations()
        revocationHandler(Set(feed.revocations.map(\.artifactSha256)))
        guard !feed.revocations.contains(where: {
            $0.artifactSha256 == storedReceipt.archiveSHA256
                || ($0.extensionId == item.id && $0.version == previous.extensionVersion)
        }) else { throw ExtensionInstallerError.revokedMarketplaceRelease }
        let timestamp = Date()
        let refreshed = MarketplaceReleaseReceipt(
            releaseIdentifier: storedReceipt.releaseIdentifier,
            extensionIdentity: storedReceipt.extensionIdentity,
            extensionVersion: storedReceipt.extensionVersion,
            providerBundleIdentifier: storedReceipt.providerBundleIdentifier,
            extensionBundleIdentifiers: storedReceipt.extensionBundleIdentifiers,
            teamIdentifier: storedReceipt.teamIdentifier,
            archiveSHA256: storedReceipt.archiveSHA256,
            archiveByteCount: storedReceipt.archiveByteCount,
            compatibility: MarketplaceCompatibilityEvidence(
                evaluatedAt: timestamp,
                hostVersion: environment.hostVersion,
                sdkVersion: ExtensionAPIVersion(
                    major: environment.sdkVersion.major,
                    minor: environment.sdkVersion.minor,
                    patch: environment.sdkVersion.patch
                ),
                macOSVersion: environment.macOSVersion,
                protocolVersion: environment.protocolVersion,
                architecture: environment.architecture
            ),
            revocation: MarketplaceRevocationEvidence(checkedAt: timestamp, status: .notRevoked),
            catalogRevision: snapshot?.revision ?? storedReceipt.catalogRevision,
            catalogKeyIdentifier: configuration.keyID,
            publisherIdentifier: storedReceipt.publisherIdentifier,
            manifestSHA256: storedReceipt.manifestSHA256,
            validationPolicyVersion: storedReceipt.validationPolicyVersion,
            verifiedAt: timestamp
        )
        try await localExtensions.rollback(item.id, marketplaceReceipt: refreshed)
    }

    private func loadVerifiedCache(now: Date = Date()) {
        guard let configuration else { return }
        do {
            guard let cached = try cache.load() else { return }
            snapshot = try MarketplaceCatalogVerifier.verify(
                cached.data,
                configuration: configuration,
                now: now,
                allowExpired: true
            )
            lastUpdatedAt = cached.verifiedAt
            isUsingCachedCatalog = true
            phase = .loaded
        } catch {
            try? cache.remove()
        }
    }
}
