import CryptoKit
import Foundation

enum MarketplaceDownloadError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case sizeMismatch(expected: Int64, actual: Int64)
    case digestMismatch

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The Hub returned an invalid download URL."
        case .invalidResponse: "The extension download failed."
        case let .sizeMismatch(expected, actual):
            "The extension size did not match the catalog (expected \(expected), received \(actual))."
        case .digestMismatch: "The extension checksum did not match the signed catalog."
        }
    }
}

struct MarketplaceArtifactDownloader: Sendable {
    @available(macOS 26.0, *)
    func download(
        release: MarketplaceRelease,
        from url: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) async throws -> URL {
        guard url.scheme == "https", release.size > 0, release.size <= 512 * 1024 * 1024 else {
            throw MarketplaceDownloadError.invalidURL
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (downloadedURL, response) = try await URLSession(configuration: configuration).download(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              response.url?.scheme == "https",
              response.url?.host == url.host,
              response.expectedContentLength <= 0 || response.expectedContentLength == release.size
        else { throw MarketplaceDownloadError.invalidResponse }

        let destination = temporaryDirectory
            .appendingPathComponent("notchkit-hub-\(UUID().uuidString)")
            .appendingPathExtension("notchkitextension")
        do {
            try FileManager.default.moveItem(at: downloadedURL, to: destination)
            try Self.verify(fileAt: destination, expectedSize: release.size, expectedSHA256: release.sha256)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    static func verify(fileAt url: URL, expectedSize: Int64, expectedSHA256: String) throws {
        guard expectedSize > 0 else {
            throw MarketplaceDownloadError.sizeMismatch(expected: expectedSize, actual: 0)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count: Int64 = 0
        while true {
            let data = try handle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty { break }
            count += Int64(data.count)
            guard count <= expectedSize else {
                throw MarketplaceDownloadError.sizeMismatch(expected: expectedSize, actual: count)
            }
            hasher.update(data: data)
        }
        guard count == expectedSize else {
            throw MarketplaceDownloadError.sizeMismatch(expected: expectedSize, actual: count)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == expectedSHA256.lowercased() else {
            throw MarketplaceDownloadError.digestMismatch
        }
    }
}
