import Foundation

enum MarketplaceCatalogResponse: Sendable {
    case modified(data: Data, etag: String?)
    case notModified
}

protocol MarketplaceCatalogFetching: Sendable {
    @available(macOS 26.0, *)
    func fetchCatalog(at url: URL, etag: String?) async throws -> MarketplaceCatalogResponse
}

struct URLSessionMarketplaceCatalogFetcher: MarketplaceCatalogFetching {
    @available(macOS 26.0, *)
    func fetchCatalog(at url: URL, etag: String?) async throws -> MarketplaceCatalogResponse {
        guard url.scheme == "https" else { throw MarketplaceCatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MarketplaceCatalogError.invalidResponse
        }
        guard response.url?.scheme == "https", response.url?.host == url.host else {
            throw MarketplaceCatalogError.invalidResponse
        }
        if response.statusCode == 304 { return .notModified }
        guard response.statusCode == 200, data.count <= 2 * 1024 * 1024 else {
            throw MarketplaceCatalogError.invalidResponse
        }
        return .modified(data: data, etag: response.value(forHTTPHeaderField: "ETag"))
    }
}

struct MarketplaceDistributionClient: Sendable {
    let configuration: MarketplaceCatalogConfiguration

    @available(macOS 26.0, *)
    func authorization(for release: MarketplaceRelease) async throws -> MarketplaceDownloadAuthorization {
        let data = try await fetch(path: release.downloadPath)
        let authorization = try MarketplaceSignedPayloadVerifier.decode(
            MarketplaceDownloadAuthorization.self,
            from: data,
            domain: "NotchKit-Hub-Release-Download-v1",
            configuration: configuration
        )
        guard authorization.apiVersion == "1",
              authorization.expiresAt > Date(),
              authorization.releaseID == release.releaseID,
              authorization.version == release.version,
              authorization.sha256 == release.sha256,
              authorization.size == release.size,
              authorization.manifestSHA256 == release.manifestSHA256,
              authorization.teamIdentifier == release.teamIdentifier,
              authorization.providerBundleIdentifier == release.providerBundleIdentifier,
              authorization.extensionBundleIdentifier == release.extensionBundleIdentifier,
              authorization.url.scheme == "https"
        else { throw MarketplaceCatalogError.invalidResponse }
        return authorization
    }

    @available(macOS 26.0, *)
    func revocations() async throws -> MarketplaceRevocationFeed {
        let data = try await fetch(path: "/v1/revocations")
        let feed = try MarketplaceSignedPayloadVerifier.decode(
            MarketplaceRevocationFeed.self,
            from: data,
            domain: "NotchKit-Hub-Revocations-v1",
            configuration: configuration
        )
        guard feed.apiVersion == "1" else { throw MarketplaceCatalogError.unsupportedAPI(feed.apiVersion) }
        return feed
    }

    @available(macOS 26.0, *)
    private func fetch(path: String) async throws -> Data {
        guard var components = URLComponents(url: configuration.catalogURL, resolvingAgainstBaseURL: false),
              path.hasPrefix("/")
        else { throw MarketplaceCatalogError.invalidResponse }
        components.path = path
        components.query = nil
        guard let url = components.url, url.scheme == "https" else {
            throw MarketplaceCatalogError.invalidResponse
        }
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.httpCookieStorage = nil
        sessionConfiguration.urlCredentialStorage = nil
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession(configuration: sessionConfiguration).data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.url?.scheme == "https",
              response.url?.host == url.host,
              response.statusCode == 200,
              data.count <= 512 * 1024
        else { throw MarketplaceCatalogError.invalidResponse }
        return data
    }
}

struct MarketplaceCachedCatalog: Sendable {
    let data: Data
    let etag: String?
    let verifiedAt: Date
}

protocol MarketplaceCatalogCaching: Sendable {
    func load() throws -> MarketplaceCachedCatalog?
    func store(_ catalog: MarketplaceCachedCatalog) throws
    func remove() throws
}

struct DiskMarketplaceCatalogCache: MarketplaceCatalogCaching, @unchecked Sendable {
    private struct Record: Codable {
        let data: Data
        let etag: String?
        let verifiedAt: Date
    }

    let fileURL: URL

    init(fileURL: URL = Self.defaultURL) {
        self.fileURL = fileURL
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("com.notchkit.app", isDirectory: true)
            .appendingPathComponent("Marketplace", isDirectory: true)
            .appendingPathComponent("catalog-v1.json", isDirectory: false)
    }

    func load() throws -> MarketplaceCachedCatalog? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: fileURL))
        return MarketplaceCachedCatalog(data: record.data, etag: record.etag, verifiedAt: record.verifiedAt)
    }

    func store(_ catalog: MarketplaceCachedCatalog) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let record = Record(data: catalog.data, etag: catalog.etag, verifiedAt: catalog.verifiedAt)
        let data = try JSONEncoder().encode(record)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }

    func remove() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
