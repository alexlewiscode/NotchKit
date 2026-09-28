import Foundation
import NotchExtensionSDK

/// The exact signed envelope served by the Hub. The payload remains base64
/// encoded so signature verification happens before JSON is interpreted.
struct MarketplaceCatalogEnvelope: Decodable, Sendable {
    let keyID: String
    let payload: String
    let signature: String
}

struct MarketplaceDownloadAuthorization: Decodable, Sendable {
    let apiVersion: String
    let releaseID: UUID
    let extensionId: ExtensionIdentity
    let version: ExtensionVersion
    let sha256: String
    let size: Int64
    let manifestSHA256: String
    let teamIdentifier: String
    let providerBundleIdentifier: String
    let extensionBundleIdentifier: String
    let url: URL
    let expiresAt: Date
}

struct MarketplaceRevocationFeed: Decodable, Sendable {
    let apiVersion: String
    let revision: String
    let generatedAt: Date
    let revocations: [MarketplaceRevocation]
}

struct MarketplaceRevocation: Decodable, Sendable {
    let extensionId: ExtensionIdentity
    let version: ExtensionVersion
    let artifactSha256: String
    let reasonCode: String
    let revokedAt: Date
}

struct MarketplaceCatalogSnapshot: Decodable, Sendable {
    let apiVersion: String
    let revision: String
    let generatedAt: Date
    let expiresAt: Date
    let entries: [MarketplaceCatalogEntry]
}

struct MarketplaceCatalogEntry: Decodable, Identifiable, Hashable, Sendable {
    let id: ExtensionIdentity
    let displayName: String
    let summary: String
    let iconSystemName: String
    let publisher: MarketplacePublisher
    let latest: MarketplaceRelease
    let versions: [MarketplaceRelease]
}

struct MarketplacePublisher: Decodable, Hashable, Sendable {
    let id: UUID
    let displayName: String
    let verified: Bool
}

struct MarketplaceRelease: Decodable, Hashable, Sendable {
    let releaseID: UUID
    let version: ExtensionVersion
    let sha256: String
    let size: Int64
    let manifestSHA256: String
    let teamIdentifier: String
    let notarized: Bool
    let stapled: Bool
    let signerType: MarketplaceSignerType
    let trustBadges: Set<MarketplaceTrustBadge>
    let artifactKind: String
    let providerBundleIdentifier: String
    let extensionBundleIdentifier: String
    let extensionPointIdentifier: String
    let capabilities: Set<String>
    let entryPoints: [ExtensionEntryPoint]
    let permissions: Set<ExtensionDeclaredPermission>
    let hostActions: Set<ExtensionHostAction>
    let compatibility: MarketplaceCompatibility
    let publishedAt: Date
    let downloadPath: String
}

enum MarketplaceSignerType: String, Decodable, Hashable, Sendable {
    case appleDevelopment
    case developerID
}

enum MarketplaceTrustBadge: String, Decodable, Hashable, Sendable {
    case notchkitTeam
    case appleDeveloper
    case reviewedSafe
}

struct MarketplaceCompatibility: Decodable, Hashable, Sendable {
    let minimumMacOSVersion: ExtensionVersion
    let supportedHostVersions: MarketplaceVersionRange
    let supportedSDKVersions: MarketplaceVersionRange
    let apiVersion: ExtensionVersion
    let protocolVersions: MarketplaceProtocolRange
    let supportedArchitectures: Set<ExtensionArchitecture>
}

struct MarketplaceVersionRange: Decodable, Hashable, Sendable {
    let minimum: ExtensionVersion
    let maximum: ExtensionVersion?

    func contains(_ version: ExtensionVersion) -> Bool {
        guard version >= minimum else { return false }
        return maximum.map { version < $0 } ?? true
    }
}

struct MarketplaceProtocolRange: Decodable, Hashable, Sendable {
    let minimum: Int
    let maximum: Int
}

enum MarketplaceCatalogError: LocalizedError, Equatable {
    case unavailable
    case unsupportedPlatform
    case invalidEnvelope
    case invalidCatalog
    case untrustedKey
    case invalidSignature
    case expired
    case unsupportedAPI(String)
    case invalidResponse
    case cacheUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "The NotchKit Hub is not configured."
        case .unsupportedPlatform: "Marketplace extensions require macOS 26 or later."
        case .invalidEnvelope: "The Hub returned invalid catalog metadata."
        case .invalidCatalog: "The Hub returned an inconsistent catalog."
        case .untrustedKey: "The Hub catalog was signed by an unknown key."
        case .invalidSignature: "The Hub catalog signature could not be verified."
        case .expired: "The Hub catalog has expired. Refresh before installing extensions."
        case let .unsupportedAPI(version): "Unsupported Hub catalog API version: \(version)"
        case .invalidResponse: "The Hub returned an invalid response."
        case .cacheUnavailable: "No verified Hub catalog is available offline."
        }
    }
}

struct MarketplaceCatalogConfiguration: Sendable {
    let catalogURL: URL
    let keyID: String
    let publicKey: Data

    static func fromBundle(_ bundle: Bundle = .main) -> Self? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: "NotchKitHubCatalogURL") as? String,
              let catalogURL = URL(string: rawURL),
              catalogURL.scheme == "https",
              let keyID = bundle.object(forInfoDictionaryKey: "NotchKitHubCatalogKeyID") as? String,
              let rawKey = bundle.object(forInfoDictionaryKey: "NotchKitHubCatalogPublicKey") as? String,
              let publicKey = Data(base64Encoded: rawKey)
        else { return nil }
        return Self(catalogURL: catalogURL, keyID: keyID, publicKey: publicKey)
    }
}
