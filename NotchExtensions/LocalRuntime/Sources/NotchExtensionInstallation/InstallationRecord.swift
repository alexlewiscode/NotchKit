import Foundation
import NotchExtensionSDK

public enum LocalInstallStatus: String, Codable, Sendable {
    case installed
    case registrationPending
    case registrationFailed
}

/// Last authority state reported by macOS. Installation code must not infer
/// this value from files, registration calls, or local preferences.
public enum SystemAuthorityStatus: String, Codable, Sendable {
    case unknown
    case awaitingUserApproval
    case approved
    case denied
}

/// Evidence observed during installation. This is deliberately not an assertion
/// that macOS has approved, activated, or enabled the system extension.
public struct InstalledCodeSignature: Codable, Equatable, Sendable {
    public let teamIdentifier: String
    public let providerDesignatedRequirement: String
    public let extensionDesignatedRequirements: [String: String]

    public init(
        teamIdentifier: String,
        providerDesignatedRequirement: String,
        extensionDesignatedRequirements: [String: String]
    ) {
        self.teamIdentifier = teamIdentifier
        self.providerDesignatedRequirement = providerDesignatedRequirement
        self.extensionDesignatedRequirements = extensionDesignatedRequirements
    }
}

public enum InstalledExtensionOrigin: String, Codable, Sendable {
    case localDeveloper
    case marketplace
}

public struct InstalledExtensionRelease: Codable, Equatable, Sendable {
    public let extensionVersion: ExtensionVersion
    public let providerBundleIdentifier: String
    public let extensionBundleIdentifiers: [String]
    public let relativeInstallPath: String
    public let manifestSHA256: String
    public let declaredPermissions: Set<ExtensionDeclaredPermission>
    public let declaredHostActions: Set<ExtensionHostAction>
    public let signature: InstalledCodeSignature
    public let origin: InstalledExtensionOrigin
    public let marketplaceReceipt: MarketplaceReleaseReceipt?
    public let installedAt: Date

    public init(record: InstalledExtensionRecord, relativeInstallPath: String? = nil) {
        extensionVersion = record.extensionVersion
        providerBundleIdentifier = record.providerBundleIdentifier
        extensionBundleIdentifiers = record.extensionBundleIdentifiers
        self.relativeInstallPath = relativeInstallPath ?? record.relativeInstallPath
        manifestSHA256 = record.manifestSHA256
        declaredPermissions = record.declaredPermissions
        declaredHostActions = record.declaredHostActions
        signature = record.signature
        origin = record.origin
        marketplaceReceipt = record.marketplaceReceipt
        installedAt = record.updatedAt
    }
}

public struct InstalledExtensionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: ExtensionIdentity
    public let extensionVersion: ExtensionVersion
    public let providerBundleIdentifier: String
    public let extensionBundleIdentifiers: [String]
    public let relativeInstallPath: String
    public let manifestSHA256: String
    public let declaredPermissions: Set<ExtensionDeclaredPermission>
    public let declaredHostActions: Set<ExtensionHostAction>
    public let signature: InstalledCodeSignature
    public let origin: InstalledExtensionOrigin
    public let marketplaceReceipt: MarketplaceReleaseReceipt?
    public let previousRelease: InstalledExtensionRelease?
    public var marketplaceRevocationStatus: MarketplaceRevocationStatus
    public let installedAt: Date
    public let updatedAt: Date
    public var desiredEnabled: Bool
    public var localStatus: LocalInstallStatus
    public var systemAuthorityStatus: SystemAuthorityStatus

    public init(
        id: ExtensionIdentity,
        extensionVersion: ExtensionVersion,
        providerBundleIdentifier: String,
        extensionBundleIdentifiers: [String],
        relativeInstallPath: String,
        manifestSHA256: String,
        declaredPermissions: Set<ExtensionDeclaredPermission>,
        declaredHostActions: Set<ExtensionHostAction>,
        signature: InstalledCodeSignature,
        origin: InstalledExtensionOrigin = .localDeveloper,
        marketplaceReceipt: MarketplaceReleaseReceipt? = nil,
        previousRelease: InstalledExtensionRelease? = nil,
        marketplaceRevocationStatus: MarketplaceRevocationStatus = .notRevoked,
        installedAt: Date,
        updatedAt: Date,
        desiredEnabled: Bool,
        localStatus: LocalInstallStatus,
        systemAuthorityStatus: SystemAuthorityStatus = .unknown
    ) {
        self.id = id
        self.extensionVersion = extensionVersion
        self.providerBundleIdentifier = providerBundleIdentifier
        self.extensionBundleIdentifiers = extensionBundleIdentifiers
        self.relativeInstallPath = relativeInstallPath
        self.manifestSHA256 = manifestSHA256
        self.declaredPermissions = declaredPermissions
        self.declaredHostActions = declaredHostActions
        self.signature = signature
        self.origin = origin
        self.marketplaceReceipt = marketplaceReceipt
        self.previousRelease = previousRelease
        self.marketplaceRevocationStatus = marketplaceRevocationStatus
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.desiredEnabled = desiredEnabled
        self.localStatus = localStatus
        self.systemAuthorityStatus = systemAuthorityStatus
    }

    private enum CodingKeys: String, CodingKey {
        case id, extensionVersion, providerBundleIdentifier, extensionBundleIdentifiers
        case relativeInstallPath, manifestSHA256, declaredPermissions, declaredHostActions
        case signature, origin, marketplaceReceipt, previousRelease, marketplaceRevocationStatus
        case installedAt, updatedAt
        case desiredEnabled, localStatus, systemAuthorityStatus
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(ExtensionIdentity.self, forKey: .id)
        extensionVersion = try values.decode(ExtensionVersion.self, forKey: .extensionVersion)
        providerBundleIdentifier = try values.decode(String.self, forKey: .providerBundleIdentifier)
        extensionBundleIdentifiers = try values.decode([String].self, forKey: .extensionBundleIdentifiers)
        relativeInstallPath = try values.decode(String.self, forKey: .relativeInstallPath)
        manifestSHA256 = try values.decode(String.self, forKey: .manifestSHA256)
        declaredPermissions = try values.decode(Set<ExtensionDeclaredPermission>.self, forKey: .declaredPermissions)
        declaredHostActions = try values.decode(Set<ExtensionHostAction>.self, forKey: .declaredHostActions)
        signature = try values.decode(InstalledCodeSignature.self, forKey: .signature)
        origin = try values.decodeIfPresent(InstalledExtensionOrigin.self, forKey: .origin) ?? .localDeveloper
        marketplaceReceipt = try values.decodeIfPresent(MarketplaceReleaseReceipt.self, forKey: .marketplaceReceipt)
        previousRelease = try values.decodeIfPresent(InstalledExtensionRelease.self, forKey: .previousRelease)
        marketplaceRevocationStatus = try values.decodeIfPresent(
            MarketplaceRevocationStatus.self,
            forKey: .marketplaceRevocationStatus
        ) ?? .notRevoked
        installedAt = try values.decode(Date.self, forKey: .installedAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        desiredEnabled = try values.decode(Bool.self, forKey: .desiredEnabled)
        localStatus = try values.decode(LocalInstallStatus.self, forKey: .localStatus)
        systemAuthorityStatus = try values.decodeIfPresent(SystemAuthorityStatus.self, forKey: .systemAuthorityStatus) ?? .unknown
    }
}

public struct InstalledExtensionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3

    public let schemaVersion: Int
    public var records: [InstalledExtensionRecord]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        records: [InstalledExtensionRecord] = []
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }
}

public protocol InstalledExtensionStore: Sendable {
    func load() throws -> InstalledExtensionSnapshot
    func save(_ snapshot: InstalledExtensionSnapshot) throws
}

public enum InstalledExtensionStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case corruptData
}

public final class JSONInstalledExtensionStore: InstalledExtensionStore, @unchecked Sendable {
    public let rootURL: URL
    public let fileURL: URL
    private let fileManager: FileManager

    public init(
        rootURL: URL,
        fileName: String = "installed-extensions.json",
        fileManager: FileManager = .default
    ) {
        self.rootURL = rootURL
        self.fileURL = rootURL.appendingPathComponent(fileName, isDirectory: false)
        self.fileManager = fileManager
    }

    public func load() throws -> InstalledExtensionSnapshot {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return InstalledExtensionSnapshot()
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode(
                InstalledExtensionSnapshot.self,
                from: Data(contentsOf: fileURL)
            )
            guard decoded.schemaVersion == 2 || decoded.schemaVersion == InstalledExtensionSnapshot.currentSchemaVersion else {
                throw InstalledExtensionStoreError.unsupportedSchemaVersion(decoded.schemaVersion)
            }
            let snapshot = decoded.schemaVersion == 2
                ? InstalledExtensionSnapshot(records: decoded.records)
                : decoded
            guard snapshot.records.allSatisfy({ record in
                switch record.origin {
                case .localDeveloper: record.marketplaceReceipt == nil
                case .marketplace: record.marketplaceReceipt != nil
                }
            }) else { throw InstalledExtensionStoreError.corruptData }
            if decoded.schemaVersion == 2 { try save(snapshot) }
            return snapshot
        } catch let error as InstalledExtensionStoreError {
            throw error
        } catch {
            // Never remove or overwrite data that could not be understood.
            throw InstalledExtensionStoreError.corruptData
        }
    }

    public func save(_ snapshot: InstalledExtensionSnapshot) throws {
        guard snapshot.schemaVersion == InstalledExtensionSnapshot.currentSchemaVersion else {
            throw InstalledExtensionStoreError.unsupportedSchemaVersion(snapshot.schemaVersion)
        }
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic])
    }
}
