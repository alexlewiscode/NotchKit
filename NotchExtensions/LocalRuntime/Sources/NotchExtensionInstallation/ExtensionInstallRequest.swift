import Foundation
import NotchExtensionSDK

public enum ExtensionInstallOperation: String, Codable, Sendable {
    case install
    case update
    case installOrUpdate
}

public enum MarketplaceRevocationStatus: String, Codable, Sendable {
    case notRevoked
    case revoked
    case unknown
}

public struct MarketplaceCompatibilityEvidence: Codable, Equatable, Sendable {
    public let evaluatedAt: Date
    public let hostVersion: ExtensionVersion
    public let sdkVersion: ExtensionAPIVersion
    public let macOSVersion: ExtensionVersion
    public let protocolVersion: Int
    public let architecture: ExtensionArchitecture

    public init(
        evaluatedAt: Date,
        hostVersion: ExtensionVersion,
        sdkVersion: ExtensionAPIVersion,
        macOSVersion: ExtensionVersion,
        protocolVersion: Int,
        architecture: ExtensionArchitecture
    ) {
        self.evaluatedAt = evaluatedAt
        self.hostVersion = hostVersion
        self.sdkVersion = sdkVersion
        self.macOSVersion = macOSVersion
        self.protocolVersion = protocolVersion
        self.architecture = architecture
    }
}

public struct MarketplaceRevocationEvidence: Codable, Equatable, Sendable {
    public let checkedAt: Date
    public let status: MarketplaceRevocationStatus

    public init(checkedAt: Date, status: MarketplaceRevocationStatus) {
        self.checkedAt = checkedAt
        self.status = status
    }
}

/// A marketplace release assertion that has already been authenticated by the
/// marketplace client. The installer still binds every assertion to the bytes,
/// package metadata, code signature, and current execution environment.
public struct MarketplaceReleaseReceipt: Codable, Equatable, Sendable {
    public let catalogRevision: String?
    public let catalogKeyIdentifier: String?
    public let publisherIdentifier: String?
    public let releaseIdentifier: String
    public let extensionIdentity: ExtensionIdentity
    public let extensionVersion: ExtensionVersion
    public let providerBundleIdentifier: String
    public let extensionBundleIdentifiers: [String]
    public let teamIdentifier: String
    public let archiveSHA256: String
    public let archiveByteCount: UInt64
    public let manifestSHA256: String?
    public let validationPolicyVersion: Int
    public let verifiedAt: Date?
    public let compatibility: MarketplaceCompatibilityEvidence
    public let revocation: MarketplaceRevocationEvidence

    public init(
        releaseIdentifier: String,
        extensionIdentity: ExtensionIdentity,
        extensionVersion: ExtensionVersion,
        providerBundleIdentifier: String,
        extensionBundleIdentifiers: [String],
        teamIdentifier: String,
        archiveSHA256: String,
        archiveByteCount: UInt64,
        compatibility: MarketplaceCompatibilityEvidence,
        revocation: MarketplaceRevocationEvidence,
        catalogRevision: String? = nil,
        catalogKeyIdentifier: String? = nil,
        publisherIdentifier: String? = nil,
        manifestSHA256: String? = nil,
        validationPolicyVersion: Int = 1,
        verifiedAt: Date? = nil
    ) {
        self.catalogRevision = catalogRevision
        self.catalogKeyIdentifier = catalogKeyIdentifier
        self.publisherIdentifier = publisherIdentifier
        self.releaseIdentifier = releaseIdentifier
        self.extensionIdentity = extensionIdentity
        self.extensionVersion = extensionVersion
        self.providerBundleIdentifier = providerBundleIdentifier
        self.extensionBundleIdentifiers = extensionBundleIdentifiers
        self.teamIdentifier = teamIdentifier
        self.archiveSHA256 = archiveSHA256
        self.archiveByteCount = archiveByteCount
        self.manifestSHA256 = manifestSHA256
        self.validationPolicyVersion = validationPolicyVersion
        self.verifiedAt = verifiedAt
        self.compatibility = compatibility
        self.revocation = revocation
    }
}

public enum ExtensionInstallTrustPolicy: Equatable, Sendable {
    case localDeveloper
    case marketplace(
        receipt: MarketplaceReleaseReceipt,
        maximumEvidenceAge: TimeInterval = 24 * 60 * 60
    )
}

public struct ExtensionInstallRequest: Sendable {
    public let archiveURL: URL
    public let operation: ExtensionInstallOperation
    public let trustPolicy: ExtensionInstallTrustPolicy

    public init(
        archiveURL: URL,
        operation: ExtensionInstallOperation,
        trustPolicy: ExtensionInstallTrustPolicy
    ) {
        self.archiveURL = archiveURL
        self.operation = operation
        self.trustPolicy = trustPolicy
    }
}
